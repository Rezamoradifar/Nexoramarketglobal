// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2Core} from "./NexoraModel2Core.sol";

/**
 * @notice Unaudited mainnet candidate; not approved for live funds.
 * BSC chain 56 and Binance-Peg USDT are fixed. Administrative/funder/allocator
 * addresses and 11 independent beneficiary controls must be verified before
 * any deployment. The contract cannot verify the source of reward funding.
 */
contract NexoraModel2MainnetVault is NexoraModel2Core {
    uint256 public constant MAINNET_CHAIN_ID = 56;
    address public constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;

    constructor(address admin_, address funder_, address allocator_, address splitter_)
        NexoraModel2Core(BSC_USDT, admin_, funder_, allocator_, splitter_, MAINNET_CHAIN_ID) {}
}
