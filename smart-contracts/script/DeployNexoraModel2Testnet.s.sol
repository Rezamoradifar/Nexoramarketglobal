// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DeployNexoraModel2Testnet
 * @notice A user-signed BSC TESTNET 97 deployment script, never mainnet.
 *
 * Requires a safe locally authenticated signing wallet for actual --broadcast.
 * NO private key or seed phrase should be put in any repository, VPS or chat.
 *
 * Existing default branch and live production domains are NEVER modified.
 * After deploying, publish TESTNET addresses, source verification and real
 * deposit/reinvest/withdrawal transaction hashes for independent review.
 */
import {NexoraModel2TestnetFactory} from "../src/NexoraModel2TestnetFactory.sol";
import {NexoraTestUSDT} from "../src/NexoraTestUSDT.sol";

interface VmNexoraDeploy {
    function envAddress(string calldata key) external returns (address);
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonAddressArray(string calldata json, string calldata key)
        external pure returns (address[] memory);
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract DeployNexoraModel2Testnet {
    uint256 private constant TESTNET_CHAIN_ID = 97;
    VmNexoraDeploy private constant vm =
        VmNexoraDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    error TestnetOnly();
    error InvalidWalletManifest();

    event Model2TestnetDeployment(
        address indexed factory,
        address indexed testToken,
        address indexed model2Vault,
        address payoutSplitter,
        uint256 chainId
    );

    function run() external returns (
        NexoraModel2TestnetFactory deployed,
        NexoraTestUSDT testToken
    ) {
        if (block.chainid != TESTNET_CHAIN_ID) revert TestnetOnly();
        address admin = vm.envAddress("NEXORA_TESTNET_ADMIN");
        address rewardsFunder = vm.envAddress("NEXORA_TESTNET_REWARDS_FUNDER");
        address allocator = vm.envAddress("NEXORA_TESTNET_ALLOCATOR");

        string memory raw = vm.readFile("config/beneficiary-wallets.candidate.json");
        address[] memory parsed = vm.parseJsonAddressArray(raw, ".constructorWallets");
        if (parsed.length != 11) revert InvalidWalletManifest();

        address[11] memory recipients;
        for (uint256 i; i < 11; ++i) recipients[i] = parsed[i];

        vm.startBroadcast();
        testToken = new NexoraTestUSDT(admin);
        deployed = new NexoraModel2TestnetFactory(
            address(testToken), admin, rewardsFunder, allocator, recipients
        );
        vm.stopBroadcast();

        emit Model2TestnetDeployment(
            address(deployed), address(testToken),
            address(deployed.vault()), address(deployed.splitter()), block.chainid
        );
    }
}
