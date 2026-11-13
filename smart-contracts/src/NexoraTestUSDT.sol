// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NexoraTestUSDT
 * @notice FAKE TEST TOKEN FOR BNB CHAIN TESTNET ONLY. HAS NO CASH VALUE.
 * This is not Tether-issued USDT and not the Binance-Peg mainnet token.
 */
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NexoraTestUSDT is ERC20, Ownable {
    uint256 public constant TESTNET_CHAIN_ID = 97;
    error TestnetOnly(uint256 actualChainId);

    constructor(address testnetFaucetAdmin)
        ERC20("Nexora Test USD Token (NO VALUE)", "NXTTEST")
        Ownable(testnetFaucetAdmin)
    {
        if (block.chainid != TESTNET_CHAIN_ID) revert TestnetOnly(block.chainid);
    }

    function mintTestTokens(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }
}
