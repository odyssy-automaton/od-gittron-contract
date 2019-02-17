pragma solidity ^0.5.2;

import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol";
import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * 
 * ERC721
 * BaseToken can be registered by any user
 * Base token has a price that sets the price for child(normal) tokens. 
 * Base token has a withdrawAddr which is the contract/wallet address to forward funds to
 * Base token has an allowed amount stored from purchases of child(normal tokens)
 * only owner of the base token can trigger withdraw
 * dev fee is subtracted from ammount allowed durring withdraw
 * a base token is requiered to launch rare token or normal token
 * BaseToken has a level which allows a number of free rare tokens
 * base token can metamorph to next level which creates a new base token and disables the current one.
 * normal tokens can be launched for the base token price
 * 
 */
contract TronToken is ERC721Full, Ownable {
    
    using SafeMath for uint;
    
    struct BaseToken {
        bool isOwner;
        bool enabled;
        uint price;
        uint allowed;
        uint level;
        uint parentTokenId;
        address payable withdrawAddr;
    }

    mapping(uint => mapping(address => BaseToken)) ownersBaseToken;
    mapping(uint => uint) rareCount;
    mapping(uint => uint) normalCount;
    mapping (address => uint256[]) internal ownerToToken;
    uint[10] levels = [2,4,8,16,32,64,128,256,512,1024];
    uint[10] raresAvailible = [4,5,6,8,10,12,15,18,21,25];
    uint devFee = 20; // 20%
    uint minimumPrice = 10000000000000000; //.01
    uint maximumPrice = 1000000000000000000; //1
    address payable devFund;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address payable _devFund
    )
    ERC721Full(_name, _symbol) public {
        devFund = _devFund;
    }
    
    function launchBaseToken(
        string memory _tokenURI,
        uint _tokenId,
        uint _price,
        address payable _withdrawAddr
    ) public {
        require(
            _price >= minimumPrice, "Price must be above minimumPrice");
        require(
            _price <= maximumPrice, "Price must be below maximumPrice");
        ownersBaseToken[_tokenId][msg.sender].isOwner = true;
        ownersBaseToken[_tokenId][msg.sender].enabled = true;
        ownersBaseToken[_tokenId][msg.sender].price = _price;
        ownersBaseToken[_tokenId][msg.sender].level = 0;
        ownersBaseToken[_tokenId][msg.sender].withdrawAddr = _withdrawAddr;
        _mint(msg.sender, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        ownerToToken[msg.sender].push(_tokenId);
    }
    
    function launchRareToken(
        uint _baseTokenId,
        uint _tokenId,
        string memory _tokenURI,
        address receiver
    ) public {
        require(
            isBaseToken(_baseTokenId), "Not a base token");
        require(
            msg.sender == ownerOf(_baseTokenId), "Not the base token holder");
        require(
             totalRare(_baseTokenId) < levels[ownersBaseToken[_baseTokenId][msg.sender].level],
             "Maximum rare tokens have been minted");
        require(
            ownersBaseToken[_baseTokenId][msg.sender].enabled, "Disabled Base Token");
    
        rareCount[_baseTokenId]++;

        _mint(receiver, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        ownerToToken[receiver].push(_tokenId);
    }
    
    function launchNormalToken(
        uint _baseTokenId,
        uint _tokenId,
        string memory _tokenURI,
        uint256 _amount,
        address receiver
    ) public payable {
        require(msg.value == _amount);
        require(
            isBaseToken(_baseTokenId), "Not a base token");
        require(
            _amount == ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].price, "Incorect value");
        require(
            ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].enabled, "Disabled Base Token");

        normalCount[_baseTokenId]++;
        
        _mint(receiver, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        ownerToToken[receiver].push(_tokenId);
        ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].allowed += _amount;
        
    }
    
    function withdraw(uint _baseTokenId) public {
        uint allowed_ = ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].allowed;
        address payable withdrawAddr_ = ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].withdrawAddr;
        require(
            isBaseToken(_baseTokenId), "Not a base token");
        require(
            msg.sender == ownerOf(_baseTokenId), "Not the base token holder");
        require(
            address(this).balance >= allowed_, 
            "insolvent");
        // is this ok?
        ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].allowed = 0;
        uint devTake = allowed_.mul(100).mul(devFee).div(10000);
        allowed_ = allowed_.sub(devTake);
        devFund.transfer(devTake);
        withdrawAddr_.transfer(allowed_);
        
    }
    
    function metamorph(
        uint _baseTokenId, 
        string memory _tokenURI,
        uint _tokenId,
        uint _price,
        address payable _withdrawAddr) public {
        require(
            _price >= minimumPrice, "Price must be above minimumPrice");
        require(
            _price <= maximumPrice, "Price must be below maximumPrice");
        require(
            msg.sender == ownerOf(_baseTokenId), "Not the base token holder");
        require(
             canMetaMorph(_baseTokenId),
             "Not enough supporters to metamorph");
        require(
            ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].enabled, "Disabled Base Token");

        ownersBaseToken[_baseTokenId][msg.sender].enabled = false;
        
        ownersBaseToken[_tokenId][msg.sender].isOwner = true;
        ownersBaseToken[_tokenId][msg.sender].enabled = true;
        ownersBaseToken[_tokenId][msg.sender].price = _price; 
        ownersBaseToken[_tokenId][msg.sender].withdrawAddr = _withdrawAddr;
        ownersBaseToken[_tokenId][msg.sender].parentTokenId = _baseTokenId;
        
        ownersBaseToken[_tokenId][msg.sender].level = ownersBaseToken[_baseTokenId][msg.sender].level + 1;
        
        rareCount[_tokenId] = rareCount[_baseTokenId];
        normalCount[_tokenId] = normalCount[_baseTokenId];
        
        _mint(msg.sender, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
        ownerToToken[msg.sender].push(_tokenId);
    }
    
    function changeMinimumPrice(uint _newPrice) public onlyOwner {
        minimumPrice = _newPrice;
    }
    
    function changeMaximumPrice(uint _newPrice) public onlyOwner {
        maximumPrice = _newPrice;
    }
    
    function canMetaMorph(uint _tokenId) public view returns(bool) {
        require(
            isBaseToken(_tokenId), "Not a base token");
        return totalNormal(_tokenId) > levels[ownersBaseToken[_tokenId][msg.sender].level];
        
    }
    
    function totalRare(uint _baseTokenId) public view returns (uint) {
        return rareCount[_baseTokenId];
    }
    
    function totalNormal(uint _baseTokenId) public view returns (uint) {
        return normalCount[_baseTokenId];
    }
    
    function totalRareAvailible(uint _baseTokenId) public view returns (uint) {
        return raresAvailible[ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].level] - totalRare(_baseTokenId);
    }
    
    function isBaseToken(uint _tokenId) public view returns (bool) {
        return ownersBaseToken[_tokenId][ownerOf(_tokenId)].isOwner;
    }
    
    function isBaseTokenEnabled(uint _tokenId) public view returns (bool) {
        require(
            isBaseToken(_tokenId), "Not a base token");
        return ownersBaseToken[_tokenId][ownerOf(_tokenId)].enabled;
    }
    
    function baseTokenParent(uint _tokenId) public view returns (uint) {
        require(
            isBaseToken(_tokenId), "Not a base token");
        return ownersBaseToken[_tokenId][ownerOf(_tokenId)].parentTokenId;
    }
    
    function baseTokenLevel(uint _tokenId) public view returns (uint) {
        require(
            isBaseToken(_tokenId), "Not a base token");
        return ownersBaseToken[_tokenId][ownerOf(_tokenId)].level;
    }
    
    function baseTokenPrice(uint _tokenId) public view returns (uint) {
        require(
            isBaseToken(_tokenId), "Not a base token");
        return ownersBaseToken[_tokenId][ownerOf(_tokenId)].price;
    }
    
    function tokensByOwner(address _owner) public view returns (uint256[] memory) {
        return ownerToToken[_owner];
    }
    
    function allowedToWithdraw(uint _baseTokenId) public view returns (uint) {
        require(
            isBaseToken(_baseTokenId), "Not a base token");
        return ownersBaseToken[_baseTokenId][ownerOf(_baseTokenId)].allowed;
    }
}
