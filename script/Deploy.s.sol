// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentDrop} from "../src/AgentDrop.sol";
import {PioneerNFT} from "../src/PioneerNFT.sol";

/// @notice AgentDrop mainnet deploy (BNB Chain, chain id 56).
/// Order matters: PioneerNFT first, then AgentDrop, then setMinter(AgentDrop)
/// BEFORE any demo pool is created (internal security review 2026-11-21).
/// Pool creation is a separate, later step (CreatePool script / cast).
///
/// Env (all optional):
///   PIONEER_MAX_SUPPLY  default 1000
///   PIONEER_BASE_URI    default "" (set later via setBaseURI)
contract Deploy is Script {
    address internal constant SPACE_ID_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external {
        uint256 maxSupply = vm.envOr("PIONEER_MAX_SUPPLY", uint256(1000));
        string memory baseURI = vm.envOr("PIONEER_BASE_URI", string(""));

        vm.startBroadcast();

        PioneerNFT pioneer = new PioneerNFT(maxSupply, baseURI);
        AgentDrop drop = new AgentDrop(SPACE_ID_AGENT_ID);
        pioneer.setMinter(address(drop));

        vm.stopBroadcast();

        console.log("PioneerNFT:", address(pioneer));
        console.log("AgentDrop:", address(drop));
        console.log("PioneerNFT.minter:", pioneer.minter());
    }
}
