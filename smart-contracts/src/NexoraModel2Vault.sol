// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NexoraModel2Core} from "./NexoraModel2Core.sol";

/** No-value prototype; direct construction rejects non-testnet chains. */
contract NexoraModel2Vault is NexoraModel2Core {
    uint256 public constant TESTNET_CHAIN_ID = 97;

    constructor(address token_, address admin_, address funder_, address allocator_, address splitter_)
        NexoraModel2Core(token_, admin_, funder_, allocator_, splitter_, TESTNET_CHAIN_ID) {}
}
