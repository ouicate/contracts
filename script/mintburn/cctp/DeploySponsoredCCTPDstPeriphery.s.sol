// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console } from "forge-std/console.sol";
import { Variable, TypeKind } from "forge-std/LibVariable.sol";

import { DeploymentUtils } from "../../utils/DeploymentUtils.sol";
import { DonationBox } from "../../../contracts/chain-adapters/DonationBox.sol";
import { SponsoredCCTPDstPeriphery } from "../../../contracts/periphery/mintburn/sponsored-cctp/SponsoredCCTPDstPeriphery.sol";

// How to run:
// 1. source .env (needs MNEMONIC="x x x ... x")
// 2. Simulate: forge script script/mintburn/cctp/DeploySponsoredCCTPDstPeriphery.s.sol:DeploySponsoredCCTPDstPeriphery --rpc-url <network> -vvvv
// 3. Deploy:   forge script script/mintburn/cctp/DeploySponsoredCCTPDstPeriphery.s.sol:DeploySponsoredCCTPDstPeriphery --rpc-url <network> --broadcast --verify -vvvv
contract DeploySponsoredCCTPDstPeriphery is DeploymentUtils {
    function run() external {
        console.log("Deploying SponsoredCCTPDstPeriphery...");
        console.log("Chain ID:", block.chainid);
        require(
            block.chainid == 999 || block.chainid == 1,
            "Dst periphery must be deployed on HyperEVM (chain 999) or Ink (chain 57073)"
        );

        string memory deployerMnemonic = vm.envString("MNEMONIC");
        uint256 deployerPrivateKey = vm.deriveKey(deployerMnemonic, 0);
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);

        _loadConfig("./script/mintburn/cctp/config.toml", true);

        address cctpMessageTransmitter = config.get("cctpMessageTransmitter").toAddress();
        address baseToken = config.get("baseToken").toAddress();
        address multicallHandler = config.get("multicallHandler").toAddress();

        vm.startBroadcast(deployerPrivateKey);

        DonationBox donationBox = DonationBox(config.get("donationBox").toAddress());
        console.log("DonationBox:", address(donationBox));

        SponsoredCCTPDstPeriphery sponsoredCCTPDstPeriphery = new SponsoredCCTPDstPeriphery(
            cctpMessageTransmitter,
            deployer,
            address(donationBox),
            baseToken,
            multicallHandler
        );

        console.log("SponsoredCCTPDstPeriphery deployed to:", address(sponsoredCCTPDstPeriphery));

        donationBox.grantRole(donationBox.WITHDRAWER_ROLE(), address(sponsoredCCTPDstPeriphery));

        console.log("DonationBox WITHDRAWER_ROLE granted to:", address(sponsoredCCTPDstPeriphery));

        address srcPeriphery = _getOptionalAddress("sponsoredCCTPSrcPeriphery");
        if (
            srcPeriphery != address(0) &&
            !sponsoredCCTPDstPeriphery.hasRole(sponsoredCCTPDstPeriphery.DIRECT_CALLER_ROLE(), srcPeriphery)
        ) {
            sponsoredCCTPDstPeriphery.grantRole(sponsoredCCTPDstPeriphery.DIRECT_CALLER_ROLE(), srcPeriphery);
            console.log("Granted DIRECT_CALLER_ROLE to same-chain src periphery:", srcPeriphery);
        }

        vm.stopBroadcast();

        config.set("sponsoredCCTPDstPeriphery", address(sponsoredCCTPDstPeriphery));

        // Post-deployment verification.
        assertEq(address(sponsoredCCTPDstPeriphery.cctpMessageTransmitter()), cctpMessageTransmitter);
        assertEq(sponsoredCCTPDstPeriphery.baseToken(), baseToken);
        assertEq(sponsoredCCTPDstPeriphery.signer(), deployer);
        assertTrue(donationBox.hasRole(donationBox.WITHDRAWER_ROLE(), address(sponsoredCCTPDstPeriphery)));
        if (srcPeriphery != address(0)) {
            assertTrue(sponsoredCCTPDstPeriphery.hasRole(sponsoredCCTPDstPeriphery.DIRECT_CALLER_ROLE(), srcPeriphery));
        }
    }

    function _getOptionalAddress(string memory key) internal view returns (address) {
        Variable memory v = config.get(key);
        if (v.ty.kind == TypeKind.None) return address(0);
        return v.toAddress();
    }
}
