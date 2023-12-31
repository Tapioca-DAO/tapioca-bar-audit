// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./SGLCommon.sol";

// solhint-disable max-line-length

/// @title Singularity liquidation module
/// @notice Singularity module for liquidation type actions
contract SGLLiquidation is SGLCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //

    /// @notice Entry point for liquidations.
    /// @dev Will call `closedLiquidation()` if not LQ exists or no LQ bid avail exists. Otherwise use LQ.
    /// @param users An array of user addresses.
    /// @param maxBorrowParts A one-to-one mapping to `users`, contains maximum (partial) borrow amounts (to liquidate) of the respective user.
    ///        Ignore for `orderBookLiquidation()`
    /// @param swapper Contract address of the `MultiSwapper` implementation. See `setSwapper`.
    ///        Ignore for `orderBookLiquidation()`
    /// @param collateralToAssetSwapData Extra swap data
    ///        Ignore for `orderBookLiquidation()`
    /// @param usdoToBorrowedSwapData Extra swap data
    ///        Ignore for `closedLiquidation()`
    function liquidate(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        ISwapper swapper,
        bytes calldata collateralToAssetSwapData,
        bytes calldata usdoToBorrowedSwapData
    ) external notPaused {
        // Oracle can fail but we still need to allow liquidations
        (, uint256 _exchangeRate) = updateExchangeRate();
        _accrue();

        if (address(liquidationQueue) != address(0)) {
            (, bool bidAvail, uint256 bidAmount) = liquidationQueue
                .getNextAvailBidPool();
            if (bidAvail) {
                uint256 needed = 0;
                for (uint256 i = 0; i < maxBorrowParts.length; i++) {
                    needed += maxBorrowParts[i];
                }
                if (bidAmount >= needed) {
                    _orderBookLiquidation(
                        users,
                        _exchangeRate,
                        usdoToBorrowedSwapData
                    );
                    return;
                }
            }
        }
        _closedLiquidation(
            users,
            maxBorrowParts,
            swapper,
            _exchangeRate,
            collateralToAssetSwapData
        );
    }

    // ************************* //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //
    function _computeAssetAmountToSolvency(
        address user,
        uint256 _exchangeRate
    ) private view returns (uint256) {
        // accrue must have already been called!
        uint256 borrowPart = userBorrowPart[user];
        if (borrowPart == 0) return 0;
        uint256 collateralShare = userCollateralShare[user];

        Rebase memory _totalBorrow = totalBorrow;

        uint256 collateralAmountInAsset = yieldBox.toAmount(
            collateralId,
            (collateralShare *
                (EXCHANGE_RATE_PRECISION / FEE_PRECISION) *
                lqCollateralizationRate),
            false
        ) / _exchangeRate;
        // Obviously it's not `borrowPart` anymore but `borrowAmount`
        borrowPart = (borrowPart * _totalBorrow.elastic) / _totalBorrow.base;

        return
            borrowPart >= collateralAmountInAsset
                ? borrowPart - collateralAmountInAsset
                : 0;
    }

    function _orderBookLiquidation(
        address[] calldata users,
        uint256 _exchangeRate,
        bytes memory swapData
    ) private {
        uint256 allCollateralShare;
        uint256 allBorrowAmount;
        uint256 allBorrowPart;
        Rebase memory _totalBorrow = totalBorrow;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (!_isSolvent(user, _exchangeRate)) {
                uint256 borrowAmount = _computeAssetAmountToSolvency(
                    user,
                    _exchangeRate
                );

                if (borrowAmount == 0) {
                    continue;
                }

                uint256 borrowPart;
                {
                    uint256 availableBorrowPart = userBorrowPart[user];
                    borrowPart = _totalBorrow.toBase(borrowAmount, false);
                    userBorrowPart[user] = availableBorrowPart - borrowPart;
                }
                uint256 amountWithBonus = borrowAmount +
                    (borrowAmount * liquidationMultiplier) /
                    FEE_PRECISION;
                uint256 collateralShare = yieldBox.toShare(
                    collateralId,
                    (amountWithBonus * _exchangeRate) / EXCHANGE_RATE_PRECISION,
                    false
                );
                userCollateralShare[user] -= collateralShare;
                emit LogRemoveCollateral(
                    user,
                    address(liquidationQueue),
                    collateralShare
                );
                emit LogRepay(
                    address(liquidationQueue),
                    user,
                    borrowAmount,
                    borrowPart
                );

                // Keep totals
                allCollateralShare += collateralShare;
                allBorrowAmount += borrowAmount;
                allBorrowPart += borrowPart;
            }
        }
        require(allBorrowAmount != 0, "SGL: solvent");

        _totalBorrow.elastic -= uint128(allBorrowAmount);
        _totalBorrow.base -= uint128(allBorrowPart);
        totalBorrow = _totalBorrow;
        totalCollateralShare -= allCollateralShare;

        uint256 allBorrowShare = yieldBox.toShare(
            assetId,
            allBorrowAmount,
            true
        );

        // Transfer collateral to be liquidated
        yieldBox.transfer(
            address(this),
            address(liquidationQueue),
            collateralId,
            allCollateralShare
        );

        // LiquidationQueue pay debt
        liquidationQueue.executeBids(
            yieldBox.toAmount(collateralId, allCollateralShare, true),
            swapData
        );

        uint256 returnedShare = yieldBox.balanceOf(address(this), assetId) -
            uint256(totalAsset.elastic);
        uint256 extraShare = returnedShare - allBorrowShare;
        uint256 callerShare = (extraShare * callerFee) / FEE_PRECISION; // 1% goes to caller

        emit Liquidated(
            msg.sender,
            users,
            callerShare,
            returnedShare - callerShare,
            allBorrowAmount,
            allCollateralShare
        );

        yieldBox.transfer(address(this), msg.sender, assetId, callerShare);

        totalAsset.elastic += uint128(returnedShare - callerShare);
        emit LogAddAsset(
            address(liquidationQueue),
            address(this),
            returnedShare - callerShare,
            0
        );
    }

    function _updateBorrowAndCollateralShare(
        address user,
        uint256 maxBorrowPart,
        uint256 _exchangeRate
    )
        private
        returns (
            uint256 borrowAmount,
            uint256 borrowPart,
            uint256 collateralShare
        )
    {
        uint256 collateralPartInAsset = (yieldBox.toAmount(
            collateralId,
            userCollateralShare[user],
            false
        ) * EXCHANGE_RATE_PRECISION) / _exchangeRate;

        uint256 borrowAssetDecimals = asset.safeDecimals();
        uint256 collateralDecimals = collateral.safeDecimals();

        uint256 availableBorrowPart = computeClosingFactor(
            userBorrowPart[user],
            collateralPartInAsset,
            borrowAssetDecimals,
            collateralDecimals,
            FEE_PRECISION_DECIMALS
        );

        if (liquidationBonusAmount > 0) {
            availableBorrowPart =
                availableBorrowPart +
                (availableBorrowPart * liquidationBonusAmount) /
                FEE_PRECISION;
        }

        borrowPart = maxBorrowPart > availableBorrowPart
            ? availableBorrowPart
            : maxBorrowPart;

        if (borrowPart > userBorrowPart[user]) {
            borrowPart = userBorrowPart[user];
        }

        userBorrowPart[user] = userBorrowPart[user] - borrowPart;

        borrowAmount = totalBorrow.toElastic(borrowPart, false);

        uint256 amountWithBonus = borrowAmount +
            (borrowAmount * liquidationMultiplier) /
            FEE_PRECISION;
        collateralShare = yieldBox.toShare(
            collateralId,
            (amountWithBonus * _exchangeRate) / EXCHANGE_RATE_PRECISION,
            false
        );
        if (collateralShare > userCollateralShare[user]) {
            collateralShare = userCollateralShare[user];
        }
        userCollateralShare[user] -= collateralShare;
        require(borrowAmount != 0, "SGL: solvent");

        totalBorrow.elastic -= uint128(borrowAmount);
        totalBorrow.base -= uint128(borrowPart);
    }

    function _extractLiquidationFees(
        uint256 borrowShare,
        uint256 callerReward,
        address swapper
    ) private returns (uint256 feeShare, uint256 callerShare) {
        uint256 returnedShare = yieldBox.balanceOf(address(this), assetId) -
            uint256(totalAsset.elastic);
        uint256 extraShare = returnedShare - borrowShare;
        feeShare = (extraShare * protocolFee) / FEE_PRECISION; // x% of profit goes to fee.
        callerShare = (extraShare * callerReward) / FEE_PRECISION; //  y%  of profit goes to caller.

        yieldBox.transfer(address(this), penrose.feeTo(), assetId, feeShare);
        yieldBox.transfer(address(this), msg.sender, assetId, callerShare);

        totalAsset.elastic += uint128(returnedShare - feeShare - callerShare);

        emit LogAddAsset(
            swapper,
            address(this),
            extraShare - feeShare - callerShare,
            0
        );
    }

    function _liquidateUser(
        address user,
        uint256 maxBorrowPart,
        ISwapper swapper,
        uint256 _exchangeRate,
        bytes calldata dexData
    ) private {
        if (_isSolvent(user, _exchangeRate)) return;

        (
            uint256 startTVLInAsset,
            uint256 maxTVLInAsset
        ) = _computeMaxAndMinLTVInAsset(
                userCollateralShare[user],
                _exchangeRate
            );
        uint256 callerReward = _getCallerReward(
            userBorrowPart[user],
            startTVLInAsset,
            maxTVLInAsset
        );

        (
            uint256 borrowAmount,
            uint256 borrowPart,
            uint256 collateralShare
        ) = _updateBorrowAndCollateralShare(user, maxBorrowPart, _exchangeRate);
        emit LogRemoveCollateral(user, address(swapper), collateralShare);
        emit LogRepay(address(swapper), user, borrowAmount, borrowPart);

        uint256 borrowShare = yieldBox.toShare(assetId, borrowAmount, true);

        // Closed liquidation using a pre-approved swapper
        require(penrose.swappers(swapper), "SGL: Invalid swapper");

        // Swaps the users collateral for the borrowed asset
        yieldBox.transfer(
            address(this),
            address(swapper),
            collateralId,
            collateralShare
        );

        uint256 minAssetAmount = 0;
        if (dexData.length > 0) {
            minAssetAmount = abi.decode(dexData, (uint256));
        }

        ISwapper.SwapData memory swapData = swapper.buildSwapData(
            collateralId,
            assetId,
            0,
            collateralShare,
            true,
            true
        );
        swapper.swap(swapData, minAssetAmount, address(this), "");

        (uint256 feeShare, uint256 callerShare) = _extractLiquidationFees(
            borrowShare,
            callerReward,
            address(swapper)
        );

        address[] memory _users = new address[](1);
        _users[0] = user;
        emit Liquidated(
            msg.sender,
            _users,
            callerShare,
            feeShare,
            borrowAmount,
            collateralShare
        );
    }

    /// @notice Handles the liquidation of users' balances, once the users' amount of collateral is too low.
    /// @dev Closed liquidations Only, 90% of extra shares goes to caller and 10% to protocol
    /// @param users An array of user addresses.
    /// @param maxBorrowParts A one-to-one mapping to `users`, contains maximum (partial) borrow amounts (to liquidate) of the respective user.
    /// @param swapper Contract address of the `MultiSwapper` implementation. See `setSwapper`.
    /// @param swapData Swap necessar data
    function _closedLiquidation(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        ISwapper swapper,
        uint256 _exchangeRate,
        bytes calldata swapData
    ) private {
        uint256 liquidatedCount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (!_isSolvent(user, _exchangeRate)) {
                liquidatedCount++;
                _liquidateUser(
                    user,
                    maxBorrowParts[i],
                    swapper,
                    _exchangeRate,
                    swapData
                );
            }
        }
        require(liquidatedCount > 0, "SGL: no users found");
    }
}
