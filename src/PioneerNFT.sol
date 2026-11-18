// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PioneerNFT — the AgentDrop commemorative NFT
/// @notice A minimal ERC-721 minted only through AgentDrop claims (the
/// minter is set once to the AgentDrop contract). Supply is capped.
///
/// Owner powers (documented, deliberately small): the owner can set the
/// minter address and the metadata base URI. The contract holds no funds
/// and the owner cannot mint directly, transfer users' NFTs, or pause
/// anything.
contract PioneerNFT {
    string public name = "AgentDrop Pioneer";
    string public symbol = "PIONEER";
    uint256 public immutable maxSupply;

    address public owner;
    address public minter;
    string public baseURI;

    uint256 private _nextTokenId = 1;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner_, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner_, address indexed operator, bool approved);
    event MinterSet(address indexed minter);
    event BaseURISet(string baseURI);

    error NotOwner();
    error NotMinter();
    error SoldOut();
    error ZeroAddress();
    error NotAuthorized();
    error NonexistentToken();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 maxSupply_, string memory baseURI_) {
        require(maxSupply_ > 0, "maxSupply=0");
        owner = msg.sender;
        maxSupply = maxSupply_;
        baseURI = baseURI_;
    }

    function setMinter(address minter_) external onlyOwner {
        if (minter_ == address(0)) revert ZeroAddress();
        minter = minter_;
        emit MinterSet(minter_);
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        baseURI = baseURI_;
        emit BaseURISet(baseURI_);
    }

    /// @notice Mint the next Pioneer NFT. Only the minter (AgentDrop).
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert NotMinter();
        if (to == address(0)) revert ZeroAddress();
        tokenId = _nextTokenId;
        if (tokenId > maxSupply) revert SoldOut();
        _nextTokenId = tokenId + 1;
        _owners[tokenId] = to;
        _balances[to] += 1;
        emit Transfer(address(0), to, tokenId);
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    // --- ERC-721 ---

    function balanceOf(address account) external view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        if (o == address(0)) revert NonexistentToken();
        return o;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId);
        return string(abi.encodePacked(baseURI, _toString(tokenId), ".json"));
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        if (msg.sender != o && !_operatorApprovals[o][msg.sender]) revert NotAuthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) external view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        if (o != from) revert NotAuthorized();
        if (to == address(0)) revert ZeroAddress();
        if (msg.sender != o && _tokenApprovals[tokenId] != msg.sender && !_operatorApprovals[o][msg.sender]) {
            revert NotAuthorized();
        }
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            // IERC721Receiver check
            (bool ok, bytes memory data) = to.call(
                abi.encodeWithSignature(
                    "onERC721Received(address,address,uint256,bytes)", msg.sender, from, tokenId, ""
                )
            );
            require(
                ok && data.length == 32 && abi.decode(data, (bytes4)) == bytes4(0x150b7a02),
                "unsafe recipient"
            );
        }
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data_) external {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            (bool ok, bytes memory data) = to.call(
                abi.encodeWithSignature("onERC721Received(address,address,uint256,bytes)", msg.sender, from, tokenId, data_)
            );
            require(
                ok && data.length == 32 && abi.decode(data, (bytes4)) == bytes4(0x150b7a02),
                "unsafe recipient"
            );
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0x80ac58cd // ERC-721
            || interfaceId == 0x5b5e139f; // ERC-721 metadata
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
