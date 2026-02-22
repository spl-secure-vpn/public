// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }
    modifier onlyOwner() {
        _checkOwner();
        _;
    }
    function owner() public view virtual returns (address) {
        return _owner;
    }
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );
}

contract SPLNFTSale is Ownable {
    AggregatorV3Interface internal immutable priceFeed;
    IERC721 public immutable nftContract;
    
    bool public paused;
    bool private locked;

    uint256 public constant PRICE_PER_NFT_USD = 1000; 
    uint256 public constant STALE_PRICE_DELAY = 3600; 
    
    uint256 public nextTokenIdIndex = 0; 
    uint256[] public availableTokenIds;

    event NftPurchased(address indexed buyer, uint256 quantity, uint256 ethSpent);

    constructor(address _nftContract, address _priceFeed) Ownable(msg.sender) {
        nftContract = IERC721(_nftContract);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    modifier nonReentrant() {
        require(!locked, "Reentrancy protection");
        locked = true;
        _;
        locked = false;
    }

    function supportPrivacy(uint256 quantity) external payable nonReentrant {
        require(!paused, "Contract is paused");
        require(quantity > 0 && quantity <= 15, "Can buy 1-15 NFTs");
        require(nextTokenIdIndex + quantity <= availableTokenIds.length, "Not enough NFTs in stock");

        uint256 requiredEth = getRequiredEth(quantity);
        require(msg.value >= requiredEth, "Insufficient ETH sent");

        ( , int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid Oracle Price");
        require(block.timestamp - updatedAt <= STALE_PRICE_DELAY, "Price data too old");

        if (msg.value > requiredEth) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - requiredEth}("");
            require(refundSuccess, "Refund failed");
        }

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = availableTokenIds[nextTokenIdIndex];
            nftContract.transferFrom(address(this), msg.sender, tokenId);
            nextTokenIdIndex++;
        }

        emit NftPurchased(msg.sender, quantity, requiredEth);
    }

    function getRequiredEth(uint256 quantity) public view returns (uint256) {
        ( , int256 price, , , ) = priceFeed.latestRoundData();
        if (price <= 0) return 0;
        return (PRICE_PER_NFT_USD * quantity * 1e26) / uint256(price);
    }

    function setPaused(bool _state) external onlyOwner {
        paused = _state;
    }

    function addAvailableTokens(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            availableTokenIds.push(tokenIds[i]);
        }
    }

    function withdrawEth() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }

    function withdrawNfts(uint256[] calldata tokenIds) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            nftContract.transferFrom(address(this), owner(), tokenIds[i]);
        }
    }

    receive() external payable {}
}
