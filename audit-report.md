# KDAO 스마트 컨트랙트 정적 분석 보고서

**날짜**: 2026-03-03
**분석 대상**: `src/KDAOMembershipNFT.sol`, `src/KDAOGovernor.sol`
**도구**: Slither v0.11.5, Solc 0.8.24, Forge v1.5.0
**테스트 결과**: 15/15 통과

---

## 요약

| 심각도 | 건수 |
|--------|------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 3 |
| Informational | 3 |

프로젝트 소스(`src/`)에서 Critical/High/Medium 취약점은 발견되지 않았습니다.
컨트랙트 로직은 OpenZeppelin v5 표준 구현을 올바르게 상속하며,
Soulbound 제약·기수 관리·거버넌스 파라미터 모두 의도에 맞게 동작합니다.
발견된 항목은 방어적 코딩 강화와 운영 설계에 관한 사항입니다.

---

## 분석 범위

| 파일 | 라인 수 | 설명 |
|------|---------|------|
| `src/KDAOMembershipNFT.sol` | 152 | Soulbound 멤버십 NFT (ERC721Votes) |
| `src/KDAOGovernor.sol` | 107 | 거버넌스 컨트랙트 (OZ Governor v5) |

의존성(`lib/openzeppelin-contracts/`) 및 테스트·배포 스크립트는 분석 범위에서 제외합니다.

---

## 발견 사항

### [L-01] EnumerableSet 반환값 미검증

**위치**: `KDAOMembershipNFT.sol:90`, `KDAOMembershipNFT.sol:131`
**Slither 탐지**: `unused-return`

```solidity
// safeMint (line 90)
_cohortTokens[cohortId].add(tokenId);   // 반환값 bool 무시

// _update (line 131)
_cohortTokens[tokenCohort[tokenId]].remove(tokenId);  // 반환값 bool 무시
```

**설명**
`EnumerableSet.add()`는 원소가 새로 추가되었을 때 `true`를, 이미 존재하면 `false`를 반환합니다.
`EnumerableSet.remove()`는 원소가 제거되었을 때 `true`를, 존재하지 않으면 `false`를 반환합니다.

**현재 코드에서의 실제 위험도**

- `add`: `_nextTokenId++`로 tokenId가 자동 증가하므로 중복이 불가능합니다. 항상 `true`.
- `remove`: `safeMint`에서 항상 `add`를 선행하므로 번(burn) 시점에 원소가 반드시 존재합니다. 항상 `true`.

현재 코드 흐름에서는 실제 오류가 발생하지 않으나, 미래 리팩터링 시 데이터 정합성이
깨져도 조용히 실패할 수 있습니다.

**권고**
`assert`로 반환값을 검증합니다.

```solidity
// safeMint
bool added = _cohortTokens[cohortId].add(tokenId);
assert(added);

// _update (burn 경로)
bool removed = _cohortTokens[tokenCohort[tokenId]].remove(tokenId);
assert(removed);
```

---

### [L-02] registerCohort 날짜 유효성 검사 없음

**위치**: `KDAOMembershipNFT.sol:69`

```solidity
function registerCohort(uint256 cohortId, uint256 termStart, uint256 termEnd) external onlyOwner {
    cohorts[cohortId] = CohortInfo({termStart: termStart, termEnd: termEnd});
    _cohortRegistered[cohortId] = true;
}
```

**설명**
`termEnd < termStart`인 잘못된 날짜를 등록해도 revert되지 않습니다.
또한 이미 등록된 `cohortId`를 재호출하면 기존 기수의 임기 정보가 **조용히 덮어써집니다**.
기존 NFT는 새 임기 정보를 가리키게 됩니다.

**권고**

```solidity
function registerCohort(uint256 cohortId, uint256 termStart, uint256 termEnd) external onlyOwner {
    require(termEnd > termStart, "termEnd must be after termStart");
    require(!_cohortRegistered[cohortId], "cohort already registered");
    cohorts[cohortId] = CohortInfo({termStart: termStart, termEnd: termEnd});
    _cohortRegistered[cohortId] = true;
}
```

임기 수정이 필요하다면 별도의 `updateCohortTerm` 함수로 분리하는 것을 권고합니다.

---

### [L-03] revokeByCohort 가스 한도 초과 가능성

**위치**: `KDAOMembershipNFT.sol:104`

```solidity
function revokeByCohort(uint256 cohortId) external onlyOwner {
    uint256[] memory tokens = _cohortTokens[cohortId].values();
    for (uint256 i = 0; i < tokens.length; i++) {
        _burn(tokens[i]);   // 매 반복마다 다수의 storage write
    }
}
```

**설명**
`_burn`은 내부적으로 `ERC721Enumerable`, `ERC721Votes`, `EnumerableSet` 등 여러 스토리지를
수정합니다. 기수당 운영진이 수십 명 이상일 경우, 단일 트랜잭션의 가스 소비가
Ethereum 블록 가스 한도(~30M gas)에 근접할 수 있습니다.

**추산**: `_burn` 1회 ≈ 30,000–50,000 gas. 기수 60명 기준 ≈ 1.8M–3M gas로
현실적인 학회 규모에서는 문제가 없습니다.

**권고**
현재 학회 운영 규모(10~20명)에서는 즉각적인 위험이 없습니다.
향후 규모가 크게 확장될 경우, 분할 실행 패턴(`revokeByCohortBatch(cohortId, offset, limit)`)을
고려합니다.

---

### [I-01] _increaseBalance — Slither false positive

**위치**: `KDAOMembershipNFT.sol:137`
**Slither 탐지**: `dead-code`

```solidity
function _increaseBalance(address account, uint128 amount)
    internal
    override(ERC721, ERC721Enumerable, ERC721Votes)
{
    super._increaseBalance(account, amount);
}
```

**설명**
Slither가 직접 호출처가 없다는 이유로 dead code로 분류했습니다.
이 함수는 `ERC721`, `ERC721Enumerable`, `ERC721Votes`의 다중 상속 충돌을
해소하기 위한 **필수 override**입니다. 컴파일러가 요구하며, 실제로는
OpenZeppelin 내부 호출 체인을 통해 실행됩니다. 조치 불필요.

---

### [I-02] votingDelay = 0 설계 고려사항

**위치**: `KDAOGovernor.sol:28`

```solidity
GovernorSettings(0, 21600, 1)  // votingDelay=0
```

**설명**
`votingDelay = 0`이면 제안이 생성된 블록의 다음 블록부터 즉시 투표가 시작됩니다.
이 설계는 운영진이 NFT 취득 후 바로 투표에 참여할 수 없다는 것을 의미합니다.
NFT를 받은 블록의 투표권은 체크포인트 메커니즘 상 아직 반영되지 않으므로,
신규 운영진은 NFT 수령 다음 블록부터 투표할 수 있습니다.

Soulbound 특성으로 인해 flashloan 공격은 불가능하므로 보안 취약점은 아닙니다.
다만 긴급 제안을 저지할 시간이 없다는 운영 리스크가 있습니다.

**권고**
운영 정책에 따라 1~10 블록의 votingDelay 설정을 검토할 수 있습니다.
현재는 학회 내부 소규모 DAO이므로 현행 유지도 무방합니다.

---

### [I-03] bootstrap 기간 중 배포자 단독 통제 가능성

**위치**: `script/DeployKDAO.s.sol`

**설명**
배포 스크립트가 배포자에게 NFT 1개를 발급합니다. 총 NFT가 1개인 상태에서
quorum(50%)은 1표로 만족됩니다. 나머지 운영진에게 NFT가 발급되기 전까지
배포자가 어떤 거버넌스 제안이든 단독으로 통과시킬 수 있습니다.

이는 설계된 동작(bootstrap)이며, 배포자를 신뢰한다는 전제 하에 작동합니다.
보안 위협이 아닌 중앙화 리스크입니다.

**권고**
`Deploy` 섹션의 "Bootstrap 전략"에 서술된 대로, 배포 시 확정된 운영진 전원에게
NFT를 발급하면 이 기간을 최소화할 수 있습니다.

---

## 컴파일러 분석

```
Solc 0.8.24 — Compiler run successful (0 warnings)
```

컴파일러 경고 없음. `^0.8.24`는 정수 오버플로가 기본 revert되고,
커스텀 에러, `unchecked` 블록 등이 지원되는 안정적인 버전입니다.

---

## 테스트 커버리지

```
Ran 15 tests — 15 passed, 0 failed
```

| 테스트 | 검증 내용 |
|--------|-----------|
| `test_FullProposalLifecycle` | 전체 거버넌스 흐름 (제안→투표→큐→실행) |
| `test_Soulbound` | Transfer 차단 |
| `test_RevokeByCohort` / `Partial` | 기수 전체·일부 회수 |
| `test_CohortTransition` | 기수 전환 원자적 실행 |
| `test_ProposalDefeatedQuorumNotMet` | Quorum 미달 시 부결 |
| `test_ProposalThresholdReverts` | NFT 없는 계정의 제안 차단 |
| `test_VoteDelegation` | 투표권 위임 |
| `test_MintUnregisteredCohortReverts` | 미등록 기수 mint 차단 |
| `test_UnauthorizedRevokeReverts` | 비소유자 revoke 차단 |
| `test_TreasuryReceivesETH` | Timelock ETH 수신 |

핵심 시나리오는 모두 커버되어 있습니다.

---

## 결론

KDAO 컨트랙트는 OpenZeppelin의 검증된 구현을 올바르게 조합하여 작성되었으며,
자체 로직의 취약점은 발견되지 않았습니다.
발견된 세 가지 Low 항목은 방어적 코딩 강화를 위한 권고이며,
즉각적인 보안 위험으로 이어지지는 않습니다.

실제 운영 전에 아래 항목의 적용을 권장합니다.

- [L-01] `assert`로 EnumerableSet 반환값 검증 추가
- [L-02] `registerCohort`에 날짜 범위 및 중복 등록 방지 검사 추가
- [I-03] 배포 시 확정된 운영진 전원에게 NFT를 발급하여 bootstrap 기간 최소화
