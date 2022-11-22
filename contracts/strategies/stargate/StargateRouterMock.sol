// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol';
import '@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol';

import '../../singularity/legacy/mocks/ERC20Mock.sol';

contract StargateRouterMock {
    using BoringERC20 for IERC20;

    IERC20 public stgToken;

    constructor(address _stgToken) {
        stgToken = IERC20(_stgToken);
    }

    function instantRedeemLocal(
        uint16,
        uint256 _amountLP,
        address _to
    ) external returns (uint256) {
        stgToken.safeTransferFrom(msg.sender, address(this), _amountLP);
        safeTransferETH(_to, _amountLP); //we assume contract has eth
        return _amountLP;
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'StargateStrategy: ETH transfer failed');
    }

    receive() external payable {}
}