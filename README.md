# KDAO - Kaist Blockchain Alumni Community

카이스트 블록체인 학회 OraKle의 Alumni를 위한 EVM 기반 온체인 커뮤니티 DAO입니다.
멤버십 NFT를 통해 1인 1표 거버넌스를 실현하며, [Tally](https://www.tally.xyz/) 웹앱에서 바로 사용할 수 있습니다.

## Architecture

```
KDAOMembershipNFT (ERC-721 Votes)
        │  1 NFT = 1 투표권
        ▼
   KDAOGovernor (OpenZeppelin Governor v5)
        │  제안 → 투표 → 큐 → 실행
        ▼
  TimelockController (Treasury + 실행 지연)
```

## Contracts

### KDAOMembershipNFT

Alumni 멤버십을 나타내는 NFT입니다. 각 NFT는 거버넌스에서 1표의 투표권을 가집니다.

- **표준**: ERC-721 + ERC721Enumerable + ERC721Votes (EIP-5805)
- **민팅**: Owner(배포 후에는 TimelockController = DAO)만 가능
- **위임(Delegation)**: 투표권을 본인 또는 다른 멤버에게 위임 가능

### KDAOGovernor

OpenZeppelin Governor v5 기반의 거버넌스 컨트랙트입니다. Tally와 완벽 호환됩니다.

| 파라미터 | 값 | 설명 |
|---|---|---|
| Voting Delay | 7,200 blocks (~1일) | 제안 생성 후 투표 시작까지 대기 시간 |
| Voting Period | 50,400 blocks (~1주) | 투표 진행 기간 |
| Proposal Threshold | 1 | 제안을 생성하려면 NFT 1개 필요 |
| Quorum | 10% | 전체 supply 대비 최소 투표 참여율 |
| Timelock Delay | 1일 | 투표 통과 후 실행까지 대기 시간 |

### TimelockController

OpenZeppelin 표준 TimelockController를 사용합니다. DAO의 Treasury 역할을 겸하며, 통과된 제안은 1일 지연 후 실행됩니다.

## What You Can Do

- **멤버십 관리**: DAO 거버넌스를 통해 새로운 Alumni에게 멤버십 NFT를 발급
- **제안 및 투표**: NFT 보유자는 누구나 제안을 생성하고, For / Against / Abstain으로 투표
- **Treasury 운용**: TimelockController에 보관된 ETH/토큰을 거버넌스 투표로 집행
- **파라미터 변경**: Voting Delay, Voting Period, Quorum 등을 거버넌스 제안으로 변경
- **Tally 연동**: 배포 후 Governor 주소를 Tally에 등록하면 웹 UI에서 모든 기능 사용 가능

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
# 테스트용 계정을 "deployer"라는 이름으로 저장
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

```bash
# 변수 설정 (위 배포 출력에서 복사)
NFT=<KDAOMembershipNFT 주소>
TIMELOCK=<TimelockController 주소>
GOVERNOR=<KDAOGovernor 주소>
RPC=http://127.0.0.1:8545
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# --- 배포 직후에는 NFT 소유권이 TimelockController에 있으므로,
# --- 멤버십 발급을 위해서는 TimelockController를 통해 실행해야 합니다.

# 1) NFT 민팅 (TimelockController를 통해)
MINT_DATA=$(cast calldata "safeMint(address)" $DEPLOYER)

cast send $TIMELOCK \
  "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $NFT 0 $MINT_DATA 0x0000000000000000000000000000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000000000000000000000000001 0 \
  --rpc-url $RPC --private-key $PK

# 시간 경과 시뮬레이션 (Timelock delay = 1일)
cast rpc anvil_increaseTime 86400 --rpc-url $RPC
cast rpc anvil_mine 1 --rpc-url $RPC

cast send $TIMELOCK \
  "execute(address,uint256,bytes,bytes32,bytes32)" \
  $NFT 0 $MINT_DATA 0x0000000000000000000000000000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000000000000000000000000001 \
  --rpc-url $RPC --private-key $PK

# 2) 투표권 위임 (자기 자신에게)
cast send $NFT "delegate(address)" $DEPLOYER --rpc-url $RPC --private-key $PK
cast rpc anvil_mine 1 --rpc-url $RPC

# 3) 투표권 확인
cast call $NFT "getVotes(address)(uint256)" $DEPLOYER --rpc-url $RPC
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

## Project Structure

```
kdao/
├── src/
│   ├── KDAOMembershipNFT.sol   # Alumni 멤버십 NFT (ERC-721 Votes)
│   └── KDAOGovernor.sol        # 거버넌스 컨트랙트 (OZ Governor v5)
├── script/
│   └── DeployKDAO.s.sol        # 배포 스크립트
├── test/
│   └── KDAOGovernor.t.sol      # 테스트 (9 tests)
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
