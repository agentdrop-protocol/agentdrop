// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for the SPACE ID Agent ID contract (BNB Chain).
/// Agent ID is a non-transferable ERC-721 ("name.ai"); each user can hold
/// at most one, so `balanceOf(account) > 0` is a complete holder check and
/// one claim per address is equivalent to one claim per Agent ID.
interface IAgentId {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IMintableNft {
    function mint(address to) external returns (uint256 tokenId);
}

/// @title AgentDrop — free claim pools gated by Agent ID
/// @notice Anyone can create a pool of ERC-20 tokens (or a mint-on-claim NFT
/// pool) that only Agent ID holders can claim from, once per address per
/// pool. Creators deposit the full pool amount up front and can reclaim
/// whatever is unclaimed after the pool ends.
///
/// Owner powers: this contract has NO owner and no admin functions. The
/// Agent ID contract address is immutable. Nobody — including the deployer —
/// can move pool funds except claimers (during the window) and the pool's
/// own creator (unclaimed remainder, only after the pool ends).
contract AgentDrop {
    IAgentId public immutable agentId;

    struct Pool {
        address creator;
        address token; // ERC-20 token, or the NFT contract when `isNft`
        bool isNft;
        uint256 amountPerClaim; // ERC-20 amount per claim (unused for NFT pools)
        uint256 maxClaims;
        uint256 claimed;
        uint64 startTime;
        uint64 endTime;
        bool remainderReclaimed;
    }

    Pool[] public pools;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    bool private _locked;

    event PoolCreated(
        uint256 indexed poolId,
        address indexed creator,
        address indexed token,
        bool isNft,
        uint256 amountPerClaim,
        uint256 maxClaims,
        uint64 startTime,
        uint64 endTime
    );
    event Claimed(uint256 indexed poolId, address indexed claimer);
    event RemainderReclaimed(uint256 indexed poolId, address indexed creator, uint256 amount);

    error NotAgentIdHolder();
    error AlreadyClaimed();
    error PoolNotActive();
    error PoolSoldOut();
    error PoolNotEnded();
    error NotPoolCreator();
    error AlreadyReclaimed();
    error InvalidWindow();
    error InvalidAmount();
    error TransferFailed();

    modifier nonReentrant() {
        if (_locked) revert TransferFailed();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address agentIdContract) {
        require(agentIdContract != address(0), "agentId=0");
        agentId = IAgentId(agentIdContract);
    }

    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    /// @notice Create an ERC-20 pool. Pulls `amountPerClaim * maxClaims`
    /// tokens from the creator into this contract.
    function createTokenPool(
        address token,
        uint256 amountPerClaim,
        uint256 maxClaims,
        uint64 startTime,
        uint64 endTime
    ) external nonReentrant returns (uint256 poolId) {
        if (amountPerClaim == 0 || maxClaims == 0) revert InvalidAmount();
        if (endTime <= startTime || endTime <= block.timestamp) revert InvalidWindow();

        uint256 total = amountPerClaim * maxClaims;
        if (!IERC20(token).transferFrom(msg.sender, address(this), total)) {
            revert TransferFailed();
        }

        poolId = pools.length;
        pools.push(
            Pool({
                creator: msg.sender,
                token: token,
                isNft: false,
                amountPerClaim: amountPerClaim,
                maxClaims: maxClaims,
                claimed: 0,
                startTime: startTime,
                endTime: endTime,
                remainderReclaimed: false
            })
        );
        emit PoolCreated(poolId, msg.sender, token, false, amountPerClaim, maxClaims, startTime, endTime);
    }

    /// @notice Create a mint-on-claim NFT pool. The NFT contract must have
    /// this contract set as its minter. Nothing is deposited.
    function createNftPool(address nft, uint256 maxClaims, uint64 startTime, uint64 endTime)
        external
        returns (uint256 poolId)
    {
        if (maxClaims == 0) revert InvalidAmount();
        if (endTime <= startTime || endTime <= block.timestamp) revert InvalidWindow();

        poolId = pools.length;
        pools.push(
            Pool({
                creator: msg.sender,
                token: nft,
                isNft: true,
                amountPerClaim: 0,
                maxClaims: maxClaims,
                claimed: 0,
                startTime: startTime,
                endTime: endTime,
                remainderReclaimed: false
            })
        );
        emit PoolCreated(poolId, msg.sender, nft, true, 0, maxClaims, startTime, endTime);
    }

    /// @notice Claim from a pool. Caller must hold an Agent ID and must not
    /// have claimed from this pool before. One claim per address per pool.
    function claim(uint256 poolId) external nonReentrant {
        Pool storage pool = pools[poolId];
        if (block.timestamp < pool.startTime || block.timestamp >= pool.endTime) {
            revert PoolNotActive();
        }
        if (pool.claimed >= pool.maxClaims) revert PoolSoldOut();
        if (hasClaimed[poolId][msg.sender]) revert AlreadyClaimed();
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();

        hasClaimed[poolId][msg.sender] = true;
        pool.claimed += 1;

        if (pool.isNft) {
            IMintableNft(pool.token).mint(msg.sender);
        } else {
            if (!IERC20(pool.token).transfer(msg.sender, pool.amountPerClaim)) {
                revert TransferFailed();
            }
        }
        emit Claimed(poolId, msg.sender);
    }

    /// @notice After a token pool ends, its creator withdraws the unclaimed
    /// remainder. NFT pools hold no funds, so there is nothing to reclaim.
    function reclaimRemainder(uint256 poolId) external nonReentrant {
        Pool storage pool = pools[poolId];
        if (msg.sender != pool.creator) revert NotPoolCreator();
        if (block.timestamp < pool.endTime) revert PoolNotEnded();
        if (pool.remainderReclaimed) revert AlreadyReclaimed();
        pool.remainderReclaimed = true;

        if (pool.isNft) {
            emit RemainderReclaimed(poolId, msg.sender, 0);
            return;
        }
        uint256 remaining = (pool.maxClaims - pool.claimed) * pool.amountPerClaim;
        if (remaining > 0) {
            if (!IERC20(pool.token).transfer(msg.sender, remaining)) {
                revert TransferFailed();
            }
        }
        emit RemainderReclaimed(poolId, msg.sender, remaining);
    }
}
