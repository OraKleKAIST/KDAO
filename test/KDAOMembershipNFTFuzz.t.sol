// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {KDAOMembershipNFT} from "../src/KDAOMembershipNFT.sol";
import {KDAOGovernor} from "../src/KDAOGovernor.sol";

/// @notice Fuzz tests for KDAOMembershipNFT.
///
/// 유닛 테스트와의 차이:
///   - 유닛 테스트: 개발자가 직접 고른 특정 입력으로 특정 동작을 검증
///   - Fuzz 테스트: Foundry가 수백~수천 개의 랜덤 입력을 대입하여
///                  "어떤 입력에서도 이 성질은 성립해야 한다"를 검증
///
/// 입력 제어 도구:
///   - vm.assume(cond) : 조건 불만족 시 해당 입력을 버림 (주소 필터링에 적합)
///   - bound(v, lo, hi): 입력을 버리지 않고 [lo, hi] 범위로 접음 (숫자 범위에 필수)
contract KDAOMembershipNFTFuzzTest is Test {
    KDAOMembershipNFT public nft;
    TimelockController public timelock;

    address public deployer = makeAddr("deployer");

    uint256 constant COHORT_1 = 1;
    uint256 constant TERM_START_1 = 1_700_000_000;
    uint256 constant TERM_END_1 = 1_715_000_000;

    function setUp() public {
        vm.startPrank(deployer);

        nft = new KDAOMembershipNFT(deployer);

        address[] memory empty = new address[](0);
        timelock = new TimelockController(1 hours, empty, empty, deployer);

        // Governor는 이 파일에서 직접 사용하지 않으나 실제 배포 환경과
        // 동일하게 timelock에 권한을 이전한다.
        KDAOGovernor governor = new KDAOGovernor(IVotes(address(nft)), timelock);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        nft.transferOwnership(address(timelock));

        vm.stopPrank();
    }

    // ── 헬퍼 ──────────────────────────────────────────────────────────────

    function _registerCohort1() internal {
        vm.prank(address(timelock));
        nft.registerCohort(COHORT_1, TERM_START_1, TERM_END_1);
    }

    function _mint(address to) internal returns (uint256 tokenId) {
        vm.prank(address(timelock));
        tokenId = nft.safeMint(to, COHORT_1);
    }

    // =========================================================================
    // 접근 제어(Access Control) — "어떤 주소든 owner가 아니면 안 된다"
    // =========================================================================

    /// @notice timelock 이외의 어떤 주소도 mint할 수 없다.
    ///
    /// 유닛 테스트에서는 alice, bob 등 몇 개 주소만 검증했지만,
    /// Fuzz 테스트는 Foundry가 생성한 임의의 주소 전체를 커버한다.
    function testFuzz_OnlyOwnerCanMint(address caller) public {
        _registerCohort1();

        // timelock(owner)은 제외 — 이 케이스는 유닛 테스트가 담당
        vm.assume(caller != address(timelock));

        vm.prank(caller);
        vm.expectRevert();
        nft.safeMint(makeAddr("recipient"), COHORT_1);
    }

    /// @notice timelock 이외의 어떤 주소도 revoke할 수 없다.
    function testFuzz_OnlyOwnerCanRevoke(address caller) public {
        _registerCohort1();
        uint256 tokenId = _mint(makeAddr("holder"));

        vm.assume(caller != address(timelock));

        vm.prank(caller);
        vm.expectRevert();
        nft.revoke(tokenId);
    }

    // =========================================================================
    // Soulbound — "어떤 수신자에게도 전송이 막혀야 한다"
    // =========================================================================

    /// @notice mint 받은 NFT는 어떤 주소로도 전송할 수 없다.
    ///
    /// `recipient`가 address(0)이면 burn으로 처리되어 SoulboundTransferNotAllowed가
    /// 발생하지 않으므로 assume으로 제외한다.
    function testFuzz_SoulboundBlocksTransferToAnyAddress(address recipient) public {
        _registerCohort1();
        address holder = makeAddr("holder");
        uint256 tokenId = _mint(holder);

        // address(0)으로의 전송은 burn이므로 제외
        vm.assume(recipient != address(0));

        vm.prank(holder);
        vm.expectRevert(KDAOMembershipNFT.SoulboundTransferNotAllowed.selector);
        nft.transferFrom(holder, recipient, tokenId);
    }

    // =========================================================================
    // 상태 일관성(State Consistency) — "N번 mint하면 상태가 정확히 N만큼 증가"
    // =========================================================================

    /// @notice N개를 mint하면 totalSupply와 cohortTokens 길이가 모두 N이어야 한다.
    ///
    /// bound()를 사용해 n을 1~30 사이로 제한한다.
    /// vm.assume(n > 0 && n <= 30)을 쓰면 대부분의 입력이 버려져
    /// "too many rejects" 에러가 발생할 수 있다.
    function testFuzz_MintIncrementsTotalSupply(uint256 n) public {
        n = bound(n, 1, 30);
        _registerCohort1();

        for (uint256 i = 0; i < n; i++) {
            // makeAddr로 인덱스마다 고유한 주소 생성 (중복 방지)
            _mint(makeAddr(string(abi.encode(i))));
        }

        assertEq(nft.totalSupply(), n);
        assertEq(nft.cohortTokens(COHORT_1).length, n);
    }

    /// @notice N개를 mint한 뒤 revokeByCohort하면 상태가 0으로 돌아온다.
    ///
    /// mint와 revoke가 서로 대칭적으로 동작하는지 확인한다.
    function testFuzz_RevokeByCohortClearsAll(uint256 n) public {
        n = bound(n, 1, 30);
        _registerCohort1();

        for (uint256 i = 0; i < n; i++) {
            _mint(makeAddr(string(abi.encode(i))));
        }

        assertEq(nft.totalSupply(), n);

        vm.prank(address(timelock));
        nft.revokeByCohort(COHORT_1);

        assertEq(nft.totalSupply(), 0);
        assertEq(nft.cohortTokens(COHORT_1).length, 0);
    }

    // =========================================================================
    // 데이터 무결성(Data Integrity) — "입력값이 그대로 저장되어야 한다"
    // =========================================================================

    /// @notice registerCohort에 전달한 값이 그대로 저장되어야 한다.
    ///
    /// 어떤 cohortId·날짜 조합이 들어오더라도 매핑에 정확히 저장되는지
    /// 확인한다. (잘못된 타입 변환이나 해시 충돌 등을 검출)
    function testFuzz_RegisterCohortStoresDates(uint256 cohortId, uint256 termStart, uint256 termEnd) public {
        vm.prank(address(timelock));
        nft.registerCohort(cohortId, termStart, termEnd);

        (uint256 storedStart, uint256 storedEnd) = nft.cohorts(cohortId);
        assertEq(storedStart, termStart);
        assertEq(storedEnd, termEnd);
    }

    /// @notice 등록되지 않은 cohortId로 mint하면 항상 revert된다.
    ///
    /// setUp에서 아무 cohort도 등록하지 않으므로 모든 cohortId가 대상이다.
    function testFuzz_MintToUnregisteredCohortReverts(uint256 cohortId) public {
        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(KDAOMembershipNFT.CohortNotRegistered.selector, cohortId));
        nft.safeMint(makeAddr("recipient"), cohortId);
    }

    // =========================================================================
    // 투표권 위임(Delegation) — "위임한 주소에 정확히 1표가 이전되어야 한다"
    // =========================================================================

    /// @notice NFT 보유자가 어떤 주소로 위임해도 그 주소의 투표권이 1이 된다.
    ///
    /// ERC721Votes의 체크포인트는 delegate 호출 다음 블록부터 반영되므로
    /// vm.roll(block.number + 1)이 필요하다.
    function testFuzz_DelegateTransfersVotingPower(address delegatee) public {
        // address(0) 위임은 투표권 포기로 처리되므로 제외
        vm.assume(delegatee != address(0));

        _registerCohort1();
        address holder = makeAddr("holder");
        _mint(holder);

        vm.prank(holder);
        nft.delegate(delegatee);

        vm.roll(block.number + 1);

        assertEq(nft.getVotes(delegatee), 1);
    }
}
