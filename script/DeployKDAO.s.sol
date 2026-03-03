// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {KDAOMembershipNFT} from "../src/KDAOMembershipNFT.sol";
import {KDAOGovernor} from "../src/KDAOGovernor.sol";

contract DeployKDAO is Script {
    function run() external {
        // Sender is determined by the CLI flag:
        //   --account <keystore>   (recommended for testnet/mainnet)
        //   --private-key 0x...    (Anvil local only)
        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. Deploy membership NFT (deployer is initial owner for setup)
        KDAOMembershipNFT nft = new KDAOMembershipNFT(deployer);
        console.log("KDAOMembershipNFT:", address(nft));

        // 2. Deploy TimelockController (1 day min delay)
        //    - Empty proposers/executors for now; will grant to Governor below
        //    - deployer as temporary admin for role setup
        address[] memory emptyArray = new address[](0);
        TimelockController timelock =
            new TimelockController({minDelay: 1 hours, proposers: emptyArray, executors: emptyArray, admin: deployer});
        console.log("TimelockController:", address(timelock));

        // 3. Deploy Governor
        KDAOGovernor governor = new KDAOGovernor(IVotes(address(nft)), timelock);
        console.log("KDAOGovernor:", address(governor));

        // 4. Grant roles to Governor on the TimelockController
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // 5. Renounce deployer's admin role on TimelockController
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // 6. Bootstrap: register cohort 1 and mint one NFT to deployer before
        //    ownership moves to Timelock. Without this, no one can propose since
        //    Governor requires proposalThreshold = 1 vote.
        nft.registerCohort(1, block.timestamp, block.timestamp + 15552000);
        nft.safeMint(deployer, 1);
        console.log("Bootstrap NFT minted to deployer:", deployer);

        // 7. Transfer NFT ownership to TimelockController (DAO controls minting)
        nft.transferOwnership(address(timelock));

        vm.stopBroadcast();

        console.log("---");
        console.log("Deployment complete. Register the Governor on Tally with address:", address(governor));
    }
}
