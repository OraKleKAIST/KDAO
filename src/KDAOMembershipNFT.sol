// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title KDAO Membership NFT
/// @notice Alumni membership NFT for the KDAO community. Each NFT represents
///         one vote in governance. Only the owner (initially the deployer, later
///         the DAO's TimelockController) can mint new memberships.
contract KDAOMembershipNFT is ERC721, ERC721Enumerable, ERC721Votes, Ownable {
    uint256 private _nextTokenId;

    constructor(address initialOwner)
        ERC721("KDAO Membership", "KDAO")
        EIP712("KDAO Membership", "1")
        Ownable(initialOwner)
    {}

    /// @notice Mint a membership NFT to a new alumni member.
    /// @param to The address of the new member.
    function safeMint(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    // --- Overrides required by Solidity for diamond inheritance ---

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Votes)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 amount)
        internal
        override(ERC721, ERC721Enumerable, ERC721Votes)
    {
        super._increaseBalance(account, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
