// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentDrop} from "../src/AgentDrop.sol";
import {PioneerNFT} from "../src/PioneerNFT.sol";

interface IAgentIdReal {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice BSC-fork tests against the REAL SPACE ID Agent ID contract.
/// Run: BSC_RPC_URL=https://bsc-dataseed.binance.org forge test --match-contract AgentDropForkTest -vv
/// (or any BSC RPC in BSC_RPC_URL). No on-chain tx: everything runs on a local fork.
contract AgentDropForkTest is Test {
    address constant AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    // Koko's Binance Agentic Wallet — known Agent ID holder ("kokoaugust").
    address constant BAW = 0xC268d5199dAc0EC52c90Cf813696c683F952A913;
    address constant NON_HOLDER = address(0xBEEF);

    AgentDrop drop;
    PioneerNFT nft;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC_URL", string("https://bsc-dataseed.binance.org"));
        vm.createSelectFork(rpc);
        drop = new AgentDrop(AGENT_ID);
        nft = new PioneerNFT(100, "https://agentdrop.kokoaugust.workers.dev/meta/");
        nft.setMinter(address(drop));
    }

    function test_realAgentId_balanceOf_BAW() public view {
        assertGt(IAgentIdReal(AGENT_ID).balanceOf(BAW), 0, "BAW must hold an Agent ID on mainnet");
    }

    function test_realAgentId_balanceOf_nonHolderIsZero() public view {
        assertEq(IAgentIdReal(AGENT_ID).balanceOf(NON_HOLDER), 0);
    }

    function test_fork_nftPool_claimByRealHolder_mintsPioneer() public {
        uint256 poolId = drop.createNftPool(
            address(nft), 10, uint64(block.timestamp), uint64(block.timestamp + 1 days)
        );
        vm.prank(BAW);
        drop.claim(poolId);
        assertEq(nft.balanceOf(BAW), 1);
        assertEq(nft.ownerOf(1), BAW);
        assertEq(nft.totalMinted(), 1);
    }

    function test_fork_claimByNonHolder_reverts() public {
        uint256 poolId = drop.createNftPool(
            address(nft), 10, uint64(block.timestamp), uint64(block.timestamp + 1 days)
        );
        vm.prank(NON_HOLDER);
        vm.expectRevert(AgentDrop.NotAgentIdHolder.selector);
        drop.claim(poolId);
    }

    function test_fork_doubleClaimByRealHolder_reverts() public {
        uint256 poolId = drop.createNftPool(
            address(nft), 10, uint64(block.timestamp), uint64(block.timestamp + 1 days)
        );
        vm.prank(BAW);
        drop.claim(poolId);
        vm.prank(BAW);
        vm.expectRevert(AgentDrop.AlreadyClaimed.selector);
        drop.claim(poolId);
    }
}
