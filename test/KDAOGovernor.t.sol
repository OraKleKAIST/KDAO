// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {KDAOMembershipNFT} from "../src/KDAOMembershipNFT.sol";
import {KDAOGovernor} from "../src/KDAOGovernor.sol";

contract KDAOGovernorTest is Test {
    KDAOMembershipNFT public nft;
    TimelockController public timelock;
    KDAOGovernor public governor;

    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    uint256 constant TIMELOCK_DELAY = 1 days;
    // Governor settings (must match constructor)
    uint256 constant VOTING_DELAY = 7200;
    uint256 constant VOTING_PERIOD = 50400;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy NFT
        nft = new KDAOMembershipNFT(deployer);

        // Deploy TimelockController
        address[] memory empty = new address[](0);
        timelock = new TimelockController(TIMELOCK_DELAY, empty, empty, deployer);

        // Deploy Governor
        governor = new KDAOGovernor(IVotes(address(nft)), timelock);

        // Configure timelock roles
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Transfer NFT ownership to timelock
        nft.transferOwnership(address(timelock));

        vm.stopPrank();
    }

    // ========== Membership NFT Tests ==========

    function test_MintAndDelegate() public {
        // Mint via timelock (simulate governance action)
        _mintViaTimelock(alice);

        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.ownerOf(0), alice);

        // Alice delegates to herself
        vm.prank(alice);
        nft.delegate(alice);

        // Move 1 block so checkpoint is recorded
        vm.roll(block.number + 1);

        assertEq(nft.getVotes(alice), 1);
    }

    function test_UnauthorizedMintReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.safeMint(alice);
    }

    // ========== Governor Lifecycle Tests ==========

    function test_FullProposalLifecycle() public {
        // Setup: mint NFTs and delegate
        _mintViaTimelock(alice);
        _mintViaTimelock(bob);
        _mintViaTimelock(carol);

        vm.prank(alice);
        nft.delegate(alice);
        vm.prank(bob);
        nft.delegate(bob);
        vm.prank(carol);
        nft.delegate(carol);

        vm.roll(block.number + 1);

        // Fund the timelock (treasury)
        vm.deal(address(timelock), 1 ether);

        // Create proposal: send 0.1 ETH to alice
        address[] memory targets = new address[](1);
        targets[0] = alice;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.1 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Send 0.1 ETH to Alice for community work";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Check state: Pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Check state: Active
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // Vote: alice For, bob For, carol Abstain
        vm.prank(alice);
        governor.castVote(proposalId, 1); // For
        vm.prank(bob);
        governor.castVote(proposalId, 1); // For
        vm.prank(carol);
        governor.castVote(proposalId, 2); // Abstain

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Check state: Succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Check state: Queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // Advance past timelock delay
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Execute
        uint256 aliceBalanceBefore = alice.balance;
        governor.execute(targets, values, calldatas, descHash);

        // Check state: Executed
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(alice.balance - aliceBalanceBefore, 0.1 ether);
    }

    function test_ProposalDefeatedByQuorum() public {
        // Mint 10 NFTs to different members
        address[] memory members = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            members[i] = makeAddr(string(abi.encodePacked("m", vm.toString(i))));
            _mintViaTimelock(members[i]);
            vm.prank(members[i]);
            nft.delegate(members[i]);
        }

        vm.roll(block.number + 1);

        // Propose (member 0 has 1 NFT, meets proposal threshold)
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(members[0]);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test quorum");

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // No one votes → quorum not reached → Defeated
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_ProposalThreshold() public {
        // Alice has no NFT, cannot propose
        vm.prank(alice);
        vm.expectRevert();
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        governor.propose(targets, values, calldatas, "Should fail");
    }

    function test_GovernorSettings() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), 1);
        assertEq(governor.quorumNumerator(), 10);
        assertEq(governor.quorumDenominator(), 100);
    }

    function test_TimelockIsExecutor() public view {
        assertEq(governor.timelock(), address(timelock));
    }

    function test_TreasuryReceivesETH() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(timelock).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(timelock).balance, 1 ether);
    }

    function test_VoteDelegation() public {
        _mintViaTimelock(alice);
        _mintViaTimelock(bob);

        // Bob delegates to Alice
        vm.prank(alice);
        nft.delegate(alice);
        vm.prank(bob);
        nft.delegate(alice);

        vm.roll(block.number + 1);

        // Alice should have 2 votes
        assertEq(nft.getVotes(alice), 2);
        assertEq(nft.getVotes(bob), 0);
    }

    // ========== Helpers ==========

    /// @dev Mint an NFT to `to` by scheduling + executing through the timelock.
    ///      We use vm.prank on the timelock to simulate a passed governance action.
    function _mintViaTimelock(address to) internal {
        // Direct call from timelock (simulating an executed proposal)
        vm.prank(address(timelock));
        nft.safeMint(to);
    }
}
