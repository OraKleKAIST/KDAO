// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title KDAO Membership NFT
/// @notice Soulbound governance NFT for KDAO club officers.
///         Each NFT represents one vote and is tied to a cohort with a fixed term.
///         Only the owner (TimelockController) can mint, revoke, and manage cohorts.
contract KDAOMembershipNFT is ERC721, ERC721Enumerable, ERC721Votes, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when attempting to transfer a soulbound token.
    error SoulboundTransferNotAllowed();

    /// @notice Thrown when referencing a cohort that has not been registered.
    error CohortNotRegistered(uint256 cohortId);

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    struct CohortInfo {
        uint256 termStart; // unix timestamp
        uint256 termEnd; // unix timestamp
    }

    uint256 private _nextTokenId;

    /// @notice Cohort term information indexed by cohort ID.
    mapping(uint256 cohortId => CohortInfo) public cohorts;

    /// @notice Which cohort each token belongs to.
    mapping(uint256 tokenId => uint256 cohortId) public tokenCohort;

    /// @dev Active token IDs per cohort (updated on mint/revoke).
    mapping(uint256 cohortId => EnumerableSet.UintSet) private _cohortTokens;

    /// @dev Track registered cohorts to validate minting.
    mapping(uint256 cohortId => bool) private _cohortRegistered;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner)
        ERC721("KDAO Membership", "KDAO")
        EIP712("KDAO Membership", "1")
        Ownable(initialOwner)
    {}

    // -------------------------------------------------------------------------
    // Cohort management
    // -------------------------------------------------------------------------

    /// @notice Register a new cohort with its term dates.
    /// @param cohortId  Cohort identifier (e.g. 1 for 1st generation).
    /// @param termStart Unix timestamp of the term start date.
    /// @param termEnd   Unix timestamp of the term end date.
    function registerCohort(uint256 cohortId, uint256 termStart, uint256 termEnd) external onlyOwner {
        cohorts[cohortId] = CohortInfo({termStart: termStart, termEnd: termEnd});
        _cohortRegistered[cohortId] = true;
    }

    /// @notice Returns all active token IDs belonging to a cohort.
    function cohortTokens(uint256 cohortId) external view returns (uint256[] memory) {
        return _cohortTokens[cohortId].values();
    }

    // -------------------------------------------------------------------------
    // Minting & revoking
    // -------------------------------------------------------------------------

    /// @notice Mint a membership NFT to a new officer.
    /// @param to       Recipient address.
    /// @param cohortId The cohort this officer belongs to (must be registered).
    function safeMint(address to, uint256 cohortId) external onlyOwner returns (uint256) {
        if (!_cohortRegistered[cohortId]) revert CohortNotRegistered(cohortId);
        uint256 tokenId = _nextTokenId++;
        tokenCohort[tokenId] = cohortId;
        _cohortTokens[cohortId].add(tokenId);
        _safeMint(to, tokenId);
        return tokenId;
    }

    /// @notice Revoke (burn) a single officer's membership NFT.
    /// @param tokenId The token to burn.
    function revoke(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    /// @notice Revoke all membership NFTs belonging to a cohort at once.
    ///         Used during cohort transitions.
    /// @param cohortId The cohort whose NFTs will all be burned.
    function revokeByCohort(uint256 cohortId) external onlyOwner {
        // Snapshot the set into memory before burning modifies it.
        uint256[] memory tokens = _cohortTokens[cohortId].values();
        for (uint256 i = 0; i < tokens.length; i++) {
            _burn(tokens[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Internal overrides
    // -------------------------------------------------------------------------

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Votes)
        returns (address)
    {
        // Soulbound: only mint (from == 0) and burn (to == 0) are allowed.
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert SoulboundTransferNotAllowed();
        }

        address previousOwner = super._update(to, tokenId, auth);

        // On burn, remove from cohort tracking.
        if (to == address(0)) {
            _cohortTokens[tokenCohort[tokenId]].remove(tokenId);
        }

        return previousOwner;
    }

    function _increaseBalance(address account, uint128 amount)
        internal
        override(ERC721, ERC721Enumerable, ERC721Votes)
    {
        super._increaseBalance(account, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
