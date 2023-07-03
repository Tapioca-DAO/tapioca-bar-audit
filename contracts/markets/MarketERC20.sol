// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IERC20} from "@boringcrypto/boring-solidity/contracts/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/*

__/\\\\\\\\\\\\\\\_____/\\\\\\\\\_____/\\\\\\\\\\\\\____/\\\\\\\\\\\_______/\\\\\_____________/\\\\\\\\\_____/\\\\\\\\\____        
 _\///////\\\/////____/\\\\\\\\\\\\\__\/\\\/////////\\\_\/////\\\///______/\\\///\\\________/\\\////////____/\\\\\\\\\\\\\__       
  _______\/\\\________/\\\/////////\\\_\/\\\_______\/\\\_____\/\\\_______/\\\/__\///\\\____/\\\/____________/\\\/////////\\\_      
   _______\/\\\_______\/\\\_______\/\\\_\/\\\\\\\\\\\\\/______\/\\\______/\\\______\//\\\__/\\\_____________\/\\\_______\/\\\_     
    _______\/\\\_______\/\\\\\\\\\\\\\\\_\/\\\/////////________\/\\\_____\/\\\_______\/\\\_\/\\\_____________\/\\\\\\\\\\\\\\\_    
     _______\/\\\_______\/\\\/////////\\\_\/\\\_________________\/\\\_____\//\\\______/\\\__\//\\\____________\/\\\/////////\\\_   
      _______\/\\\_______\/\\\_______\/\\\_\/\\\_________________\/\\\______\///\\\__/\\\_____\///\\\__________\/\\\_______\/\\\_  
       _______\/\\\_______\/\\\_______\/\\\_\/\\\______________/\\\\\\\\\\\____\///\\\\\/________\////\\\\\\\\\_\/\\\_______\/\\\_ 
        _______\///________\///________\///__\///______________\///////////_______\/////_____________\/////////__\///________\///__

*/

/// @title Market ERC20 contract
/// @notice Market ERC20 capabilitites 
contract MarketERC20 is IERC20, IERC20Permit, EIP712 {
    // ************ //
    // *** VARS *** //
    // ************ //
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
    bytes32 private constant _PERMIT_TYPEHASH_BORROW =
        keccak256(
            "PermitBorrow(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /**
     * @dev In previous versions `_PERMIT_TYPEHASH` was declared as `immutable`.
     * However, to ensure consistency with the upgradeable transpiler, we will continue
     * to reserve a slot.
     * @custom:oz-renamed-from _PERMIT_TYPEHASH
     */
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private _PERMIT_TYPEHASH_DEPRECATED_SLOT;

    /// @notice owner > balance mapping.
    mapping(address => uint256) public override balanceOf;
    /// @notice owner > spender > allowance mapping.
    mapping(address => mapping(address => uint256)) public override allowance;
    /// @notice owner > spender > allowance mapping.
    mapping(address => mapping(address => uint256)) public allowanceBorrow;
    /// @notice owner > nonce mapping. Used in `permit`.
    mapping(address => uint256) private _nonces;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    /// @notice error thrown when operation is not approved
    error NotApproved(address _from, address _operator);

    // ************** //
    // *** EVENTS *** //
    // ************** //
    /// @notice event emitted when borrow approval is performed
    event ApprovalBorrow(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // ***************** //
    // *** MODIFIERS *** //
    // ***************** //
    function _allowedLend(address from, uint share) internal {
        if (from != msg.sender) {
            if (allowance[from][msg.sender] < share) {
                revert NotApproved(from, msg.sender);
            }
            allowance[from][msg.sender] -= share;
        }
    }

    function _allowedBorrow(address from, uint share) internal {
        if (from != msg.sender) {
            if (allowanceBorrow[from][msg.sender] < share) {
                revert NotApproved(from, msg.sender);
            }
            allowanceBorrow[from][msg.sender] -= share;
        }
    }

    /// Check if msg.sender has right to execute Lend operations
    modifier allowedLend(address from, uint share) virtual {
        _allowedLend(from, share);
        _;
    }
    /// Check if msg.sender has right to execute borrow operations
    modifier allowedBorrow(address from, uint share) virtual {
        _allowedBorrow(from, share);
        _;
    }

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC20 token name.
     */
    constructor(string memory name) EIP712(name, "1") {}

    // ********************** //
    // *** VIEW FUNCTIONS *** //
    // ********************** //
    function totalSupply() public view virtual override returns (uint256) {}

    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //
    /// @notice Transfers `amount` tokens from `msg.sender` to `to`.
    /// @param to The address to move the tokens.
    /// @param amount of the tokens to move.
    /// @return (bool) Returns True if succeeded.
    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        // If `amount` is 0, or `msg.sender` is `to` nothing happens
        if (amount != 0 || msg.sender == to) {
            uint256 srcBalance = balanceOf[msg.sender];
            require(srcBalance >= amount, "ERC20: balance too low");
            if (msg.sender != to) {
                require(to != address(0), "ERC20: no zero address"); // Moved down so low balance calls safe some gas

                balanceOf[msg.sender] = srcBalance - amount; // Underflow is checked
                balanceOf[to] += amount;
            }
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfers `amount` tokens from `from` to `to`. Caller needs approval for `from`.
    /// @param from Address to draw tokens from.
    /// @param to The address to move the tokens.
    /// @param amount The token amount to move.
    /// @return (bool) Returns True if succeeded.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        // If `amount` is 0, or `from` is `to` nothing happens
        if (amount != 0) {
            uint256 srcBalance = balanceOf[from];
            require(srcBalance >= amount, "ERC20: balance too low");

            if (from != to) {
                uint256 spenderAllowance = allowance[from][msg.sender];
                // If allowance is infinite, don't decrease it to save on gas (breaks with EIP-20).
                if (spenderAllowance != type(uint256).max) {
                    require(
                        spenderAllowance >= amount,
                        "ERC20: allowance too low"
                    );
                    allowance[from][msg.sender] = spenderAllowance - amount; // Underflow is checked
                }
                require(to != address(0), "ERC20: no zero address"); // Moved down so other failed calls safe some gas

                balanceOf[from] = srcBalance - amount; // Underflow is checked
                balanceOf[to] += amount;
            }
        }
        emit Transfer(from, to, amount);
        return true;
    }

    /// @notice Approves `amount` from sender to be spend by `spender`.
    /// @param spender Address of the party that can draw from msg.sender's account.
    /// @param amount The maximum collective amount that `spender` can draw.
    /// @return (bool) Returns True if approved.
    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function approveBorrow(
        address spender,
        uint256 amount
    ) public returns (bool) {
        _approveBorrow(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20Permit-permit}.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override(IERC20, IERC20Permit) {
        _permit(true, owner, spender, value, deadline, v, r, s);
    }

    function permitBorrow(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _permit(false, owner, spender, value, deadline, v, r, s);
    }

    // ************************* //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //

    /**
     * @dev "Consume a nonce": return the current value and increment.
     *
     * _Available since v4.1._
     */
    function _useNonce(
        address owner
    ) internal virtual returns (uint256 current) {
        current = _nonces[owner]++;
    }

    function _permit(
        bool asset, // 1 = asset, 0 = collateral
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        bytes32 structHash = keccak256(
            abi.encode(
                asset ? _PERMIT_TYPEHASH : _PERMIT_TYPEHASH_BORROW,
                owner,
                spender,
                value,
                _useNonce(owner),
                deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");

        if (asset) {
            _approve(owner, spender, value);
        } else {
            _approveBorrow(owner, spender, value);
        }
    }

    function _approveBorrow(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        allowanceBorrow[owner][spender] = amount;
        emit ApprovalBorrow(owner, spender, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
