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
    address public dave = makeAddr("dave");

    uint256 constant TIMELOCK_DELAY = 1 hours;
    uint256 constant VOTING_DELAY = 0;
    uint256 constant VOTING_PERIOD = 21600; // ~3 days

    // Cohort fixture
    uint256 constant COHORT_1 = 1;
    uint256 constant TERM_START_1 = 1_700_000_000;
    uint256 constant TERM_END_1 = 1_715_000_000;

    function setUp() public {
        vm.startPrank(deployer);

        nft = new KDAOMembershipNFT(deployer);

        address[] memory empty = new address[](0);
        timelock = new TimelockController(TIMELOCK_DELAY, empty, empty, deployer);

        governor = new KDAOGovernor(IVotes(address(nft)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        nft.transferOwnership(address(timelock));

        vm.stopPrank();
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Register cohort 1 via timelock prank.
    function _registerCohort1() internal {
        vm.prank(address(timelock));
        nft.registerCohort(COHORT_1, TERM_START_1, TERM_END_1);
    }

    /// @dev Mint to `to` in cohort 1 via timelock prank.
    function _mint(address to) internal returns (uint256 tokenId) {
        vm.prank(address(timelock));
        tokenId = nft.safeMint(to, COHORT_1);
    }

    /// @dev Mint + self-delegate for `account`.
    function _mintAndDelegate(address account) internal returns (uint256 tokenId) {
        tokenId = _mint(account);
        vm.prank(account);
        nft.delegate(account);
    }

    // =========================================================================
    // Cohort management
    // =========================================================================

    function test_RegisterCohort() public {
        _registerCohort1();
        (uint256 start, uint256 end) = nft.cohorts(COHORT_1);
        assertEq(start, TERM_START_1);
        assertEq(end, TERM_END_1);
    }

    function test_MintWithCohort() public {
        _registerCohort1();
        uint256 tokenId = _mint(alice);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.tokenCohort(tokenId), COHORT_1);
        assertEq(nft.cohortTokens(COHORT_1).length, 1);
    }

    function test_MintUnregisteredCohortReverts() public {
        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(KDAOMembershipNFT.CohortNotRegistered.selector, 99));
        nft.safeMint(alice, 99);
    }

    // =========================================================================
    // Soulbound
    // =========================================================================

    function test_Soulbound() public {
        _registerCohort1();
        _mint(alice);

        vm.prank(alice);
        vm.expectRevert(KDAOMembershipNFT.SoulboundTransferNotAllowed.selector);
        nft.transferFrom(alice, bob, 0);
    }

    // =========================================================================
    // Revoke
    // =========================================================================

    function test_RevokeSingle() public {
        _registerCohort1();
        uint256 tokenId = _mint(alice);

        vm.prank(address(timelock));
        nft.revoke(tokenId);

        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.cohortTokens(COHORT_1).length, 0);
    }

    function test_RevokeByCohort() public {
        _registerCohort1();
        _mint(alice);
        _mint(bob);
        _mint(carol);

        assertEq(nft.cohortTokens(COHORT_1).length, 3);

        vm.prank(address(timelock));
        nft.revokeByCohort(COHORT_1);

        assertEq(nft.totalSupply(), 0);
        assertEq(nft.cohortTokens(COHORT_1).length, 0);
    }

    function test_RevokeByCohortPartial() public {
        _registerCohort1();
        uint256 t0 = _mint(alice);
        _mint(bob);
        _mint(carol);

        // Individually revoke alice before batch revoke
        vm.prank(address(timelock));
        nft.revoke(t0);

        assertEq(nft.cohortTokens(COHORT_1).length, 2);

        // Batch revoke the remaining two
        vm.prank(address(timelock));
        nft.revokeByCohort(COHORT_1);

        assertEq(nft.totalSupply(), 0);
        assertEq(nft.cohortTokens(COHORT_1).length, 0);
    }

    function test_UnauthorizedRevokeReverts() public {
        _registerCohort1();
        _mint(alice);

        vm.prank(alice);
        vm.expectRevert();
        nft.revoke(0);
    }

    // =========================================================================
    // Cohort transition (1기 → 2기)
    // =========================================================================

    function test_CohortTransition() public {
        // --- Setup: 1기 운영진 3명 ---
        _registerCohort1();
        _mint(alice);
        _mint(bob);
        _mint(carol);
        assertEq(nft.totalSupply(), 3);

        // --- 2기 등록 및 1기 전체 회수 + 2기 발급 (timelock이 실행) ---
        vm.startPrank(address(timelock));
        nft.revokeByCohort(COHORT_1);

        uint256 cohort2 = 2;
        nft.registerCohort(cohort2, TERM_END_1, TERM_END_1 + 15_000_000);
        nft.safeMint(dave, cohort2);
        nft.safeMint(alice, cohort2); // alice가 2기에도 운영진으로 재참여
        vm.stopPrank();

        assertEq(nft.totalSupply(), 2);
        assertEq(nft.cohortTokens(COHORT_1).length, 0);
        assertEq(nft.cohortTokens(cohort2).length, 2);
        assertEq(nft.tokenCohort(3), cohort2);
        assertEq(nft.tokenCohort(4), cohort2);
    }

    // =========================================================================
    // Governor settings
    // =========================================================================

    function test_GovernorSettings() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), 1);
        assertEq(governor.quorumNumerator(), 50);
        assertEq(governor.quorumDenominator(), 100);
        assertEq(governor.timelock(), address(timelock));
    }

    // =========================================================================
    // Full governance lifecycle
    // =========================================================================

    function test_FullProposalLifecycle() public {
        // Setup: 4명 운영진, 모두 자기 위임
        _registerCohort1();
        _mintAndDelegate(alice);
        _mintAndDelegate(bob);
        _mintAndDelegate(carol);
        _mintAndDelegate(dave);

        vm.roll(block.number + 1);

        // Fund treasury
        vm.deal(address(timelock), 1 ether);

        // Propose: send 0.1 ETH to alice
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = alice;
        values[0] = 0.1 ether;
        calldatas[0] = "";
        string memory description = "Send 0.1 ETH to Alice for ops work";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // votingDelay=0 이지만 제안 블록에서는 snapshot >= clock 이라 Pending.
        // 다음 블록으로 이동해야 Active.
        vm.roll(block.number + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // 4명 중 3명 찬성 (quorum 50% = 2표 필요, 3표 For → 통과)
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);
        vm.prank(carol);
        governor.castVote(proposalId, 1);
        vm.prank(dave); // Against
        governor.castVote(proposalId, 0);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue → 1시간 대기 → Execute
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        uint256 balanceBefore = alice.balance;
        governor.execute(targets, values, calldatas, descHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(alice.balance - balanceBefore, 0.1 ether);
    }

    function test_ProposalDefeatedQuorumNotMet() public {
        // 4명 중 1명만 찬성 → quorum 50%(2표) 미달
        _registerCohort1();
        _mintAndDelegate(alice);
        _mintAndDelegate(bob);
        _mintAndDelegate(carol);
        _mintAndDelegate(dave);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Low participation");

        vm.roll(block.number + 1); // 제안 다음 블록부터 Active

        vm.prank(alice);
        governor.castVote(proposalId, 1); // 1표만 For (quorum 2표 미달)

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_ProposalThresholdReverts() public {
        // NFT 없는 계정은 제안 불가
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "No NFT proposal");
    }

    function test_TreasuryReceivesETH() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(timelock).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(timelock).balance, 1 ether);
    }

    function test_VoteDelegation() public {
        _registerCohort1();
        _mint(alice);
        _mint(bob);

        // Bob delegates to Alice
        vm.prank(alice);
        nft.delegate(alice);
        vm.prank(bob);
        nft.delegate(alice);

        vm.roll(block.number + 1);

        assertEq(nft.getVotes(alice), 2);
        assertEq(nft.getVotes(bob), 0);
    }
}
