// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../interfaces/ISendFrom.sol";

abstract contract MagnetarActionsData {
    // GENERIC
    struct PermitData {
        address owner;
        address spender;
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct PermitAllData {
        address owner;
        address spender;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // TOFT
    struct WrapData {
        address from;
        address to;
        uint256 amount;
    }

    struct WrapNativeData {
        address to;
    }

    struct SendApprovalData {
        uint16 lzDstChainId;
        ITOFTOperations.IApproval approval;
        ITOFTOperations.SendOptions options;
    }

    struct TOFTSendAndBorrowData {
        address from;
        address to;
        uint256 amount;
        uint256 borrowAmount;
        address marketHelper;
        address market;
        uint16 lzDstChainId;
        uint256 withdrawLzFeeAmount;
        ITOFTOperations.SendOptions options;
    }

    struct TOFTSendAndLendData {
        address from;
        address to;
        uint256 amount;
        address marketHelper;
        address market;
        uint16 lzDstChainId;
        ITOFTOperations.SendOptions options;
    }

    struct TOFTSendToYBData {
        address from;
        address to;
        uint256 amount;
        uint256 assetId;
        uint16 lzDstChainId;
        ITOFTOperations.SendOptions options;
    }

    struct TOFTRetrieveYBData {
        address from;
        uint256 amount;
        uint256 assetId;
        uint16 lzDstChainId;
        address zroPaymentAddress;
        bytes airdropAdapterParam;
        bool strategyWithdrawal;
    }

    struct TOFTSendFromData {
        address from;
        uint16 dstChainId;
        bytes32 to;
        uint256 amount;
        ISendFrom.LzCallParams callParams;
    }

    // YieldBox
    struct YieldBoxDepositData {
        uint256 assetId;
        address from;
        address to;
        uint256 amount;
        uint256 share;
    }

    // Singularity
    struct SGLAddCollateralData {
        address from;
        address to;
        bool skim;
        uint256 share;
    }

    struct SGLBorrowData {
        address from;
        address to;
        uint256 amount;
    }

    struct SGLWithdrawToData {
        address from;
        uint16 dstChainId;
        bytes32 receiver;
        uint256 amount;
        bytes adapterParams;
        address payable refundAddress;
    }

    struct SGLLendData {
        address from;
        address to;
        bool skim;
        uint256 share;
    }

    struct SGLRepayData {
        address from;
        address to;
        bool skim;
        uint256 part;
    }
}

interface IPermit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface IPermitAll {
    function permitAll(
        address owner,
        address spender,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface ITOFTOperations {
    function wrap(
        address fromAddress,
        address toAddress,
        uint256 amount
    ) external;

    function wrapNative(address _toAddress) external payable;

    struct SendOptions {
        uint256 extraGasLimit;
        address zroPaymentAddress;
        bool strategyDeposit;
        bool wrap;
    }

    struct IApproval {
        address target;
        address owner;
        address spender;
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function sendApproval(
        uint16 lzDstChainId,
        IApproval calldata approval,
        SendOptions calldata options
    ) external payable;

    function sendToYBAndBorrow(
        address from,
        address to,
        uint256 amount,
        uint256 borrowAmount,
        address marketHelper,
        address market,
        uint16 lzDstChainId,
        uint256 withdrawLzFeeAmount,
        SendOptions calldata options
    ) external payable;

    function sendToYBAndLend(
        address from,
        address to,
        uint256 amount,
        address marketHelper,
        address market,
        uint16 lzDstChainId,
        SendOptions calldata options
    ) external payable;

    function sendToYB(
        address from,
        address to,
        uint256 amount,
        uint256 assetId,
        uint16 lzDstChainId,
        SendOptions calldata options
    ) external payable;

    function retrieveFromYB(
        address from,
        uint256 amount,
        uint256 assetId,
        uint16 lzDstChainId,
        address zroPaymentAddress,
        bytes memory airdropAdapterParam,
        bool strategyWithdrawal
    ) external payable;
}

interface IDepositAsset {
    function depositAsset(
        uint256 assetId,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
}

interface ISingularityOperations {
    function addCollateral(
        address from,
        address to,
        bool skim,
        uint256 share
    ) external;

    function borrow(
        address from,
        address to,
        uint256 amount
    ) external returns (uint256 part, uint256 share);

    function withdrawTo(
        address from,
        uint16 dstChainId,
        bytes32 receiver,
        uint256 amount,
        bytes calldata adapterParams,
        address payable refundAddress
    ) external payable;

    function addAsset(
        address from,
        address to,
        bool skim,
        uint256 share
    ) external returns (uint256 fraction);

    function repay(
        address from,
        address to,
        bool skim,
        uint256 part
    ) external returns (uint256 amount);
}