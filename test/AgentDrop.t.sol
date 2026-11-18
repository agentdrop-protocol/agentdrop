// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentDrop} from "../src/AgentDrop.sol";
import {PioneerNFT} from "../src/PioneerNFT.sol";

contract MockAgentId {
    mapping(address => bool) public holds;

    function setHolder(address a, bool v) external {
        holds[a] = v;
    }

    function balanceOf(address a) external view returns (uint256) {
        return holds[a] ? 1 : 0;
    }
}

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address sp, uint256 amt) external returns (bool) {
        allowance[msg.sender][sp] = amt;
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        require(balanceOf[msg.sender] >= amt, "bal");
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        require(balanceOf[from] >= amt, "bal");
        require(allowance[from][msg.sender] >= amt, "allow");
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }
}

contract AgentDropTest is Test {
    MockAgentId agentId;
    MockERC20 token;
    AgentDrop drop;
    PioneerNFT nft;

    address creator = address(0xC0FFEE);
    address holder1 = address(0xA1);
    address holder2 = address(0xA2);
    address stranger = address(0xB0B);

    uint64 start;
    uint64 end;

    function setUp() public {
        agentId = new MockAgentId();
        token = new MockERC20();
        drop = new AgentDrop(address(agentId));
        nft = new PioneerNFT(100, "https://example.invalid/pioneer/");
        nft.setMinter(address(drop));

        agentId.setHolder(holder1, true);
        agentId.setHolder(holder2, true);

        start = uint64(block.timestamp) + 10;
        end = start + 7 days;

        token.mint(creator, 1_000 ether);
        vm.prank(creator);
        token.approve(address(drop), 1_000 ether);
    }

    function _tokenPool() internal returns (uint256 id) {
        vm.prank(creator);
        id = drop.createTokenPool(address(token), 10 ether, 5, start, end);
    }

    function testCreateTokenPoolPullsDeposit() public {
        uint256 id = _tokenPool();
        assertEq(id, 0);
        assertEq(token.balanceOf(address(drop)), 50 ether);
        assertEq(drop.poolCount(), 1);
    }

    function testHolderClaimsOnce() public {
        uint256 id = _tokenPool();
        vm.warp(start + 1);
        vm.prank(holder1);
        drop.claim(id);
        assertEq(token.balanceOf(holder1), 10 ether);
        assertTrue(drop.hasClaimed(id, holder1));

        vm.prank(holder1);
        vm.expectRevert(AgentDrop.AlreadyClaimed.selector);
        drop.claim(id);
    }

    function testNonHolderCannotClaim() public {
        uint256 id = _tokenPool();
        vm.warp(start + 1);
        vm.prank(stranger);
        vm.expectRevert(AgentDrop.NotAgentIdHolder.selector);
        drop.claim(id);
    }

    function testClaimBeforeStartAndAfterEndReverts() public {
        uint256 id = _tokenPool();
        vm.prank(holder1);
        vm.expectRevert(AgentDrop.PoolNotActive.selector);
        drop.claim(id);

        vm.warp(end + 1);
        vm.prank(holder1);
        vm.expectRevert(AgentDrop.PoolNotActive.selector);
        drop.claim(id);
    }

    function testPoolSoldOut() public {
        vm.prank(creator);
        uint256 id = drop.createTokenPool(address(token), 1 ether, 1, start, end);
        vm.warp(start + 1);
        vm.prank(holder1);
        drop.claim(id);
        vm.prank(holder2);
        vm.expectRevert(AgentDrop.PoolSoldOut.selector);
        drop.claim(id);
    }

    function testReclaimRemainderAfterEnd() public {
        uint256 id = _tokenPool();
        vm.warp(start + 1);
        vm.prank(holder1);
        drop.claim(id);

        vm.warp(end + 1);
        uint256 before = token.balanceOf(creator);
        vm.prank(creator);
        drop.reclaimRemainder(id);
        // 5 claims funded, 1 claimed -> 4 * 10 ether back
        assertEq(token.balanceOf(creator) - before, 40 ether);
        assertEq(token.balanceOf(address(drop)), 0);
    }

    function testReclaimTooEarlyAndByStrangerReverts() public {
        uint256 id = _tokenPool();
        vm.prank(creator);
        vm.expectRevert(AgentDrop.PoolNotEnded.selector);
        drop.reclaimRemainder(id);

        vm.warp(end + 1);
        vm.prank(stranger);
        vm.expectRevert(AgentDrop.NotPoolCreator.selector);
        drop.reclaimRemainder(id);
    }

    function testNftPoolMintsOnClaim() public {
        vm.prank(creator);
        uint256 id = drop.createNftPool(address(nft), 10, start, end);
        vm.warp(start + 1);
        vm.prank(holder1);
        drop.claim(id);
        assertEq(nft.balanceOf(holder1), 1);
        assertEq(nft.ownerOf(1), holder1);
        assertEq(nft.totalMinted(), 1);
    }

    function testNftMintOnlyViaDrop() public {
        vm.prank(stranger);
        vm.expectRevert(PioneerNFT.NotMinter.selector);
        nft.mint(stranger);
    }
}
