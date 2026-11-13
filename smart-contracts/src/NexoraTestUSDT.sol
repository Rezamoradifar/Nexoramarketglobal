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
    constructor(address testnetFaucetAdmin)
        ERC20("Nexora Test USD Token (NO VALUE)", "NXTTEST")
        Ownable(testnetFaucetAdmin)
    {}

    function mintTestTokens(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }
}
