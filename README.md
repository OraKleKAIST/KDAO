# KDAO - 학회 운영진 의사결정 플랫폼

[![CI](https://github.com/OraKleKAIST/KDAO/actions/workflows/ci.yml/badge.svg)](https://github.com/OraKleKAIST/KDAO/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/OraKleKAIST/KDAO/branch/main/graph/badge.svg)](https://codecov.io/gh/OraKleKAIST/KDAO)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5.5.0-blue)](https://docs.openzeppelin.com/contracts/5.x/)

블록체인 학회 한 기수의 운영진들을 위한 EVM 기반 온체인 의사결정 플랫폼입니다.
운영진에게 Soulbound NFT를 발급하여 1인 1표 거버넌스를 실현하며, [Tally](https://www.tally.xyz/) 웹앱과 호환됩니다.
기수 교체 시 이전 기수 NFT를 일괄 회수하고 새 기수 운영진에게 재발급하는 기능을 제공합니다.

## Architecture

```
KDAOMembershipNFT (ERC-721 Votes, Soulbound)
        │  1 NFT = 1 투표권 · 기수별 임기 정보 포함
        ▼
   KDAOGovernor (OpenZeppelin Governor v5)
        │  제안 → 투표(3일) → 큐 → 실행
        ▼
  TimelockController (Treasury + 1시간 실행 지연)
```

## Contracts

### KDAOMembershipNFT

운영진 자격을 나타내는 Soulbound NFT입니다. 각 NFT는 거버넌스에서 1표의 투표권을 가지며 기수 임기 정보를 포함합니다.

- **표준**: ERC-721 + ERC721Enumerable + ERC721Votes (EIP-5805)
- **Soulbound**: Transfer 불가 — mint / revoke(burn)만 허용
- **기수 관리**: `registerCohort`로 기수별 임기(termStart, termEnd) 등록
- **민팅**: `safeMint(address, cohortId)` — Owner(TimelockController)만 가능
- **회수**: `revoke(tokenId)` 단일 소각 / `revokeByCohort(cohortId)` 기수 전체 소각
- **위임(Delegation)**: 투표권을 본인 또는 다른 운영진에게 위임 가능

### KDAOGovernor

OpenZeppelin Governor v5 기반의 거버넌스 컨트랙트입니다. Tally와 완벽 호환됩니다.

| 파라미터 | 값 | 설명 |
|---|---|---|
| Voting Delay | 0 blocks | 제안 즉시 다음 블록부터 투표 시작 |
| Voting Period | 21,600 blocks (~3일) | 투표 진행 기간 |
| Proposal Threshold | 1 | 제안을 생성하려면 NFT 1개 필요 |
| Quorum | 50% | 전체 운영진의 과반수 이상 참여 필요 |
| Timelock Delay | 1시간 | 투표 통과 후 실행까지 대기 시간 |

### TimelockController

OpenZeppelin 표준 TimelockController를 사용합니다. Treasury 역할을 겸하며, 통과된 제안은 1시간 후 실행됩니다.

## What You Can Do

- **운영진 발급**: 거버넌스 투표를 통해 새 기수 운영진에게 멤버십 NFT 발급
- **기수 전환**: `revokeByCohort` + `registerCohort` + `safeMint`를 하나의 제안으로 묶어 원자적 기수 교체
- **제안 및 투표**: NFT 보유자는 누구나 제안을 생성하고, For / Against / Abstain으로 투표
- **Treasury 운용**: TimelockController에 보관된 ETH/토큰을 거버넌스 투표로 집행
- **파라미터 변경**: Voting Period, Quorum 등을 거버넌스 제안으로 변경
- **Tally 연동**: 배포 후 Governor 주소를 Tally에 등록하면 웹 UI에서 모든 기능 사용 가능

### 기수 전환 제안 예시

1기 운영진 전원 회수 후 2기 운영진 발급을 **단일 제안**으로 원자적으로 실행합니다.

```
targets:   [nft, nft, nft, nft, nft]
calldatas: [
  revokeByCohort(1),              // 1기 전체 NFT 회수
  registerCohort(2, start, end),  // 2기 임기 등록
  safeMint(addr1, 2),             // 2기 운영진 발급
  safeMint(addr2, 2),
  safeMint(addr3, 2),
]
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Sepolia 테스트넷 ETH ([faucet](https://www.alchemy.com/faucets/ethereum-sepolia))
- RPC URL (Alchemy, Infura 등)

## Quick Start

```bash
# 의존성 설치
forge install

# 컴파일
forge build

# 테스트
forge test -vvv
```

## Wallet Setup

Private key를 평문으로 `.env`에 저장하는 대신, Foundry Keystore를 사용합니다.
키는 `~/.foundry/keystores/`에 AES-128-CTR로 암호화되어 저장되며,
배포 시 패스워드만 입력하면 됩니다.

```bash
# 계정을 "deployer"라는 이름으로 저장
# private key 입력 → 패스워드 설정 순서로 진행
cast wallet import deployer --interactive

# 저장된 계정 확인
cast wallet list

# 주소 확인 (이후 --sender에 사용)
cast wallet address --account deployer
```

## Deploy

### 1. 로컬 (Anvil)

로컬 테스트넷에서 빠르게 배포하고 상호작용해볼 수 있습니다.

```bash
# 터미널 1: Anvil 로컬 노드 실행
anvil
```

Anvil의 기본 계정(Account #0)으로 배포합니다.

```bash
# 터미널 2: 배포 (Anvil 기본 계정 사용)
forge script script/DeployKDAO.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

배포 후 출력되는 컨트랙트 주소를 확인합니다.

```
KDAOMembershipNFT: 0x...
TimelockController: 0x...
KDAOGovernor:       0x...
```

#### 로컬에서 상호작용 테스트

배포 후 TimelockController가 NFT의 owner이므로, Anvil의 impersonation 기능으로
Timelock 주소를 사칭하여 NFT 함수를 직접 호출합니다.
이는 실제 거버넌스 실행 시(Timelock → NFT 호출)와 동일한 흐름입니다.

```bash
# 변수 설정 (위 배포 출력에서 복사)
NFT=<KDAOMembershipNFT 주소>
TIMELOCK=<TimelockController 주소>
RPC=http://127.0.0.1:8545
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
MY_ADDR=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Timelock 주소를 impersonate (가스비 충전 포함)
cast rpc anvil_impersonateAccount $TIMELOCK --rpc-url $RPC
cast rpc anvil_setBalance $TIMELOCK 0x1000000000000000000 --rpc-url $RPC

# 1) 기수 등록 (Timelock을 사칭하여 직접 호출)
cast send $NFT \
  "registerCohort(uint256,uint256,uint256)" \
  1 $(date +%s) $(($(date +%s) + 15552000)) \
  --from $TIMELOCK --unlocked --rpc-url $RPC

# 2) NFT 민팅 (cohortId=1)
cast send $NFT \
  "safeMint(address,uint256)" \
  $MY_ADDR 1 \
  --from $TIMELOCK --unlocked --rpc-url $RPC

# 3) 투표권 위임 (자기 자신에게)
cast send $NFT "delegate(address)" $MY_ADDR --rpc-url $RPC --private-key $PK
cast rpc anvil_mine 1 --rpc-url $RPC

# 4) 투표권 확인
cast call $NFT "getVotes(address)(uint256)" $MY_ADDR --rpc-url $RPC
```

### 2. Ethereum Sepolia Testnet

Keystore를 사용하여 배포합니다. Private key가 CLI 히스토리나 환경변수에 남지 않습니다.

```bash
# 환경변수 설정 (RPC URL, Etherscan API key만 포함)
cp .env.example .env
# .env 파일을 열고 SEPOLIA_RPC_URL, ETHERSCAN_API_KEY 입력
source .env
```

```bash
# 배포 (패스워드 입력 프롬프트가 나타남)
forge script script/DeployKDAO.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --account deployer \
  --sender $(cast wallet address --account deployer) \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

배포가 완료되면 콘솔에 출력된 Governor 주소를 [Tally](https://www.tally.xyz/)에 등록하여 웹 UI에서 DAO를 관리할 수 있습니다.

#### 배포된 컨트랙트 주소 확인

배포 후 Foundry는 `broadcast/` 디렉터리에 트랜잭션 기록을 저장합니다.
`run-latest.json`에서 배포된 컨트랙트 주소를 확인할 수 있습니다.

```bash
# Sepolia 배포 주소 확인 (jq 사용)
cat broadcast/DeployKDAO.s.sol/11155111/run-latest.json \
  | jq '.transactions[] | select(.contractName != null and .contractAddress != null) | {name: .contractName, address: .contractAddress}' \
  | jq -s 'unique_by(.address)'

# 또는 cast를 활용한 개별 확인
# NFT owner가 TimelockController 주소인지 검증
cast call <NFT_ADDR> "owner()(address)" --rpc-url $SEPOLIA_RPC_URL
```

#### 테스트넷에서 상호작용 테스트

로컬과 달리 테스트넷에서는 Anvil의 impersonation을 사용할 수 없습니다.
배포 스크립트가 배포자에게 NFT 1개를 mint하므로, 배포자는 투표권을 위임한 뒤
바로 거버넌스 제안을 생성할 수 있습니다.

먼저 배포된 주소를 변수로 설정합니다.

```bash
# broadcast JSON에서 확인한 주소로 설정
NFT=<KDAOMembershipNFT 주소>
TIMELOCK=<TimelockController 주소>
GOVERNOR=<KDAOGovernor 주소>
MY_ADDR=$(cast wallet address --account deployer)
```

**읽기 전용 검증** — 배포 직후 즉시 실행 가능합니다.

```bash
# NFT owner가 TimelockController인지 확인
cast call $NFT "owner()(address)" --rpc-url $SEPOLIA_RPC_URL

# Governor에 연결된 token / timelock 주소 확인
cast call $GOVERNOR "token()(address)" --rpc-url $SEPOLIA_RPC_URL
cast call $GOVERNOR "timelock()(address)" --rpc-url $SEPOLIA_RPC_URL

# 총 발급된 NFT 수 (배포자에게 1개 발급되어 있어야 함)
cast call $NFT "totalSupply()(uint256)" --rpc-url $SEPOLIA_RPC_URL

# Quorum (가장 최근 블록 기준)
BLOCK=$(cast block-number --rpc-url $SEPOLIA_RPC_URL)
cast call $GOVERNOR "quorum(uint256)(uint256)" $((BLOCK - 1)) --rpc-url $SEPOLIA_RPC_URL
```

**투표권 위임** — 배포 직후 반드시 실행합니다.

ERC721Votes는 `delegate`를 호출해야 체크포인트가 기록되고 투표권이 활성화됩니다.
`delegate`를 호출하지 않으면 NFT를 보유하고 있어도 `getVotes`가 0을 반환하여
제안 생성이 불가능합니다.

```bash
# 1) 투표권 위임 (자기 자신에게)
cast send $NFT "delegate(address)" $MY_ADDR \
  --account deployer --rpc-url $SEPOLIA_RPC_URL

# 2) 투표권 확인 (위임 후 1블록 이후부터 반영)
cast call $NFT "getVotes(address)(uint256)" $MY_ADDR --rpc-url $SEPOLIA_RPC_URL
```

**나머지 운영진 추가 (거버넌스 제안)** — 위임 후 1블록이 지난 뒤 실행합니다.

배포자 외 나머지 운영진을 추가하려면 거버넌스 제안을 통해 mint합니다.
[Tally](https://www.tally.xyz/)에서 웹 UI로 제안하거나, `cast`로 직접 제안할 수 있습니다.

```bash
# calldata 인코딩
CALLDATA_MINT2=$(cast calldata "safeMint(address,uint256)" 0xALICE 1)
CALLDATA_MINT3=$(cast calldata "safeMint(address,uint256)" 0xBOB 1)

# Governor에 제안 생성
cast send $GOVERNOR \
  "propose(address[],uint256[],bytes[],string)" \
  "[$NFT,$NFT]" "[0,0]" "[$CALLDATA_MINT2,$CALLDATA_MINT3]" \
  "나머지 1기 운영진 NFT 발급" \
  --account deployer --rpc-url $SEPOLIA_RPC_URL
```

> **참고**: 로컬 테스트에서는 `anvil_impersonateAccount`로 Timelock을 사칭하여 NFT 함수를 직접 호출합니다.
> 테스트넷에서는 실제 거버넌스 흐름(제안 → 투표 → 큐 → 실행)을 따라야 합니다.
> 배포자 1명만 투표권을 가진 상태에서는 quorum(50%)을 혼자 만족하므로 제안을 단독으로 통과시킬 수 있습니다.

### Bootstrap 전략

Governor의 `proposalThreshold`가 1이므로, 배포 직후 아무도 NFT를 갖지 않으면
거버넌스 제안 자체가 불가능해집니다. 배포 시 최소 1명에게 NFT를 mint하여
이 부트스트랩 문제를 해결해야 합니다.

#### 현재 방식: 배포자에게 NFT 1개 발급 후 나머지를 거버넌스로 추가

배포 스크립트가 배포자에게 1기 cohort의 NFT 1개를 발급합니다.
배포자가 투표권을 위임한 뒤 나머지 운영진 mint를 제안하고 단독으로 통과시킵니다.

```
[배포] → 배포자에게 NFT 1개 mint
  → delegate()
  → 나머지 운영진 mint 제안
  → (배포자 단독 투표로 통과)
  → 전체 운영진 NFT 보유 완료
```

- 장점: 배포 전에 모든 운영진 주소가 확정되지 않아도 됩니다.
- 단점: 나머지 운영진이 추가되기 전까지 배포자가 단독으로 제안을 통과시킬 수 있습니다.

#### 권장 방식: 배포 시 확정된 운영진 전원에게 mint

배포 스크립트에 초기 운영진 주소 목록을 지정하여 배포 트랜잭션 안에서 전원에게 mint합니다.
배포 완료 즉시 거버넌스가 완전히 분산된 상태로 시작됩니다.

```solidity
// DeployKDAO.s.sol 수정 예시
address[] memory cohort1 = new address[](3);
cohort1[0] = 0xAlice...;
cohort1[1] = 0xBob...;
cohort1[2] = 0xCarol...;

nft.registerCohort(1, block.timestamp, block.timestamp + 15552000);
for (uint256 i = 0; i < cohort1.length; i++) {
    nft.safeMint(cohort1[i], 1);
}
nft.transferOwnership(address(timelock));
```

일부 주소가 미확정인 경우, 확정된 인원만 먼저 mint하고 나머지는 배포 후 거버넌스 제안으로 추가합니다.
이때 초기 mint 인원이 quorum을 만족할 수 있을 만큼 충분한지 확인합니다.

- 장점: 배포 직후부터 신뢰 가정 없이 분산 거버넌스가 작동합니다.
- 단점: 배포 전에 운영진 전원(또는 과반수)의 지갑 주소를 수집해야 합니다.

## CI

PR 및 `main` 브랜치 push 시 자동 실행됩니다. 모든 job은 `lint → build` 순서로 선행되며, 이후 병렬 실행됩니다.

| Job | 명령어 | 설명 |
|-----|--------|------|
| **lint** | `forge fmt --check` | 코드 포맷 검사. 가장 먼저 실행되어 빠른 피드백 제공. |
| **build** | `forge build --sizes` | 컴파일 + EIP-170 컨트랙트 크기(24.576 KB) 초과 여부 확인. |
| **test** | `forge test -vvv` | 전체 테스트 실행. |
| **coverage** | `forge coverage --report lcov` | `lcov.info` 생성 후 Codecov에 업로드. PR 코멘트로 커버리지 diff 자동 표시. |
| **gas-snapshot** | `forge snapshot --check` | `.gas-snapshot` 파일과 비교하여 가스 변화 감지. 증감 무관 diff 발생 시 실패 — 의도적 변경이면 `forge snapshot`으로 파일 갱신 후 커밋. |
| **slither** | `crytic/slither-action` | 정적 분석. `lib/`, `test/`, `script/` 제외, `src/`만 검사. High 이상 시 실패. 결과는 GitHub Security 탭(Code Scanning)에 SARIF로 업로드. |
| **deploy-dry-run** | `forge script` (no `--broadcast`) | 배포 스크립트를 로컬 EVM에서 시뮬레이션. 실제 네트워크 전송 없이 배포 로직의 revert 여부 사전 검출. |

### 배포 워크플로

| 워크플로 | 트리거 | 조건 |
|----------|--------|------|
| `deploy-testnet.yml` | CI 통과 후 자동 | GitHub Environments `testnet` 승인 필요 |
| `deploy-mainnet.yml` | 수동 (`workflow_dispatch`) | 확인 문자열 입력 + `mainnet` 승인 필요 |

GitHub 배포 승인 게이트 설정: `Settings → Environments → testnet / mainnet → Required Reviewers`

### gas-snapshot 갱신 방법

테스트 로직 변경으로 가스가 바뀌었다면:

```bash
forge snapshot        # .gas-snapshot 갱신
git add .gas-snapshot
git commit -m "chore: update gas snapshot"
```

## Project Structure

```
kdao/
├── src/
│   ├── KDAOMembershipNFT.sol   # 운영진 멤버십 NFT (Soulbound · 기수 관리)
│   └── KDAOGovernor.sol        # 거버넌스 컨트랙트 (OZ Governor v5)
├── script/
│   └── DeployKDAO.s.sol        # 배포 스크립트
├── test/
│   └── KDAOGovernor.t.sol      # 테스트 (15 tests)
├── foundry.toml                # Foundry 설정
└── .env.example                # 환경변수 템플릿
```

## Tech Stack

- **Solidity** ^0.8.24
- **Foundry** (Forge / Cast / Anvil)
- **OpenZeppelin Contracts** v5.5.0
- **Target Network**: Ethereum Sepolia (Tally 호환)

## License

MIT
