// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2Vault} from "./NexoraModel2Vault.sol";
import {NexoraRevenueSplitter} from "./NexoraRevenueSplitter.sol";

interface INexoraMockToken {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function owner() external view returns (address);
    function TESTNET_CHAIN_ID() external view returns (uint256);
}

/**
 * @notice Convenience factory for NO-VALUE BNB Testnet rehearsals only.
 * One selected wallet holds admin, reward-funder and allocator roles. This is
 * deliberately not independent governance and must never be used as a
 * production security model. The separate-role factory remains unchanged.
 */
contract NexoraModel2SingleWalletTestnetFactory {
    uint256 public constant TESTNET_CHAIN_ID = 97;
    NexoraModel2Vault public immutable vault;
    NexoraRevenueSplitter public immutable splitter;
    address public immutable testOwner;

    error TestnetOnly(uint256 actualChainId);
    error ZeroRole();
    error InvalidTestToken();

    event TestnetSystemCreated(address indexed vault, address indexed splitter,
                               address token, address indexed testOwner);

    constructor(address token, address owner_, address[11] memory payoutWallets) {
        if (block.chainid != TESTNET_CHAIN_ID) revert TestnetOnly(block.chainid);
        if (token == address(0) || owner_ == address(0)) revert ZeroRole();
        if (token.code.length == 0) revert InvalidTestToken();
        INexoraMockToken mockToken = INexoraMockToken(token);
        if (mockToken.decimals() != 18 || mockToken.TESTNET_CHAIN_ID() != TESTNET_CHAIN_ID ||
            mockToken.owner() != owner_ || keccak256(bytes(mockToken.symbol())) != keccak256("NXTTEST")) {
            revert InvalidTestToken();
        }

        NexoraRevenueSplitter s = new NexoraRevenueSplitter(
            token, address(this), address(this), payoutWallets
        );
        NexoraModel2Vault v = new NexoraModel2Vault(
            token, address(this), owner_, owner_, address(s)
        );
        s.grantRole(s.FUNDER_ROLE(), address(v));
        s.grantRole(s.DEFAULT_ADMIN_ROLE(), owner_);
        v.grantRole(v.DEFAULT_ADMIN_ROLE(), owner_);
        s.grantRole(s.GUARDIAN_ROLE(), owner_);
        v.grantRole(v.GUARDIAN_ROLE(), owner_);
        s.revokeRole(s.FUNDER_ROLE(), address(this));
        s.revokeRole(s.GUARDIAN_ROLE(), address(this));
        v.revokeRole(v.GUARDIAN_ROLE(), address(this));
        s.renounceRole(s.DEFAULT_ADMIN_ROLE(), address(this));
        v.renounceRole(v.DEFAULT_ADMIN_ROLE(), address(this));

        vault = v;
        splitter = s;
        testOwner = owner_;
        emit TestnetSystemCreated(address(v), address(s), token, owner_);
    }
}
