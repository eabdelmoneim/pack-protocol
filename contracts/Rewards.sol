// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Rewards is ERC1155 {

  /// @dev Address of $PACK Protocol's `pack` token.
  address public pack;

  /// @dev The token Id of the reward to mint.
  uint public nextTokenId;

  enum UnderlyingType { None, ERC20, ERC721 }

  struct Reward {
    address creator;
    string uri;
    uint supply;
    UnderlyingType underlyingType;
  }

  struct ERC721Reward {
    address nftContract;
    uint nftTokenId;
  }

  struct ERC20Reward {
    address tokenContract;
    uint shares;
    uint underlyingTokenAmount;
  }

  /// @notice Events.
  event NativeRewards(address indexed creator, uint[] rewardIds, string[] rewardURIs, uint[] rewardSupplies);
  event ERC721Rewards(address indexed creator, address indexed nftContract, uint nftTokenId, uint rewardTokenId, string rewardURI);
  event ERC721Redeemed(address indexed redeemer, address indexed nftContract, uint nftTokenId, uint rewardTokenId);
  event ERC20Rewards(address indexed creator, address indexed tokenContract, uint tokenAmount, uint rewardsMinted, string rewardURI);
  event ERC20Redeemed(address indexed redeemer, address indexed tokenContract, uint tokenAmountReceived, uint rewardAmountRedeemed);

  /// @dev Reward tokenId => Reward state.
  mapping(uint => Reward) public rewards;

  /// @dev Reward tokenId => Underlying ERC721 reward state.
  mapping(uint => ERC721Reward) public erc721Rewards;

  /// @dev Reward tokenId => Underlying ERC20 reward state.
  mapping(uint => ERC20Reward) public erc20Rewards;

  constructor(address  _pack) ERC1155("") {
    pack = _pack;
  }

  /// @notice Create native ERC 1155 rewards.
  function createNativeRewards(string[] calldata _rewardURIs, uint[] calldata _rewardSupplies) public returns (uint[] memory rewardIds) {
    require(_rewardURIs.length == _rewardSupplies.length, "Rewards: Must specify equal number of URIs and supplies.");
    require(_rewardURIs.length > 0, "Rewards: Must create at least one reward.");

    // Get tokenIds.
    rewardIds = new uint[](_rewardURIs.length);
    
    // Store reward state for each reward.
    for(uint i = 0; i < _rewardURIs.length; i++) {
      rewardIds[i] = nextTokenId;

      rewards[nextTokenId] = Reward({
        creator: msg.sender,
        uri: _rewardURIs[i],
        supply: _rewardSupplies[i],
        underlyingType: UnderlyingType.None
      });

      nextTokenId++;
    }

    // Mint reward tokens to `msg.sender`
    _mintBatch(msg.sender, rewardIds, _rewardSupplies, "");

    emit NativeRewards(msg.sender, rewardIds, _rewardURIs, _rewardSupplies);
  }

  /// @dev Creates packs with rewards.
	function createPackAtomic(
		string[] calldata _rewardURIs,
		uint[] calldata _rewardSupplies,

		string calldata _packURI,
		uint _secondsUntilOpenStart,
    uint _secondsUntilOpenEnd

	) external {
		
		uint[] memory rewardIds = createNativeRewards(_rewardURIs, _rewardSupplies);

		bytes memory args = abi.encode(_packURI, address(this), _secondsUntilOpenStart, _secondsUntilOpenEnd);
		safeBatchTransferFrom(msg.sender, pack, rewardIds, _rewardSupplies, args);
	}

  /// @dev Creates packs with rewards.
	function createPack(
		uint[] calldata _rewardIds,
		uint[] calldata _rewardAmounts,

		string calldata _packURI,
		uint _secondsUntilOpenStart,
    uint _secondsUntilOpenEnd

	) external {
    bytes memory args = abi.encode(_packURI, address(this), _secondsUntilOpenStart, _secondsUntilOpenEnd);
		safeBatchTransferFrom(msg.sender, pack, _rewardIds, _rewardAmounts, args);
  }

  /// @dev Wraps an ERC721 NFT as ERC1155 reward tokens. 
  function wrapERC721(address _nftContract, uint _tokenId, string calldata _rewardURI) external {
    require(
      IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,
      "Rewards: Only the owner of the NFT can wrap it."
    );
    require(
      IERC721(_nftContract).getApproved(_tokenId) == address(this) || IERC721(_nftContract).isApprovedForAll(msg.sender, address(this)),
      "Rewards: Must approve the contract to transfer the NFT."
    );
        
    // Transfer the NFT to this contract.
    IERC721(_nftContract).safeTransferFrom(
      msg.sender, 
      address(this), 
      _tokenId
    );

    // Mint reward tokens to `msg.sender`
    _mint(msg.sender, nextTokenId, 1, "");

    // Store reward state.
    rewards[nextTokenId] = Reward({
      creator: msg.sender,
      uri: _rewardURI,
      supply: 1,
      underlyingType: UnderlyingType.ERC721
    });       
        
    // Map the reward tokenId to the underlying NFT
    erc721Rewards[nextTokenId] = ERC721Reward({
      nftContract: _nftContract,
      nftTokenId: _tokenId
    });

    emit ERC721Rewards(msg.sender, _nftContract, _tokenId, nextTokenId, _rewardURI);

    nextTokenId++;
  }
  
  /// @dev Lets the reward owner redeem their ERC721 NFT.
  function redeemERC721(uint _rewardId) external {
    require(balanceOf(msg.sender, _rewardId) > 0, "Rewards: Cannot redeem a reward you do not own.");
        
    // Burn the reward token
    _burn(msg.sender, _rewardId, 1);
        
    // Transfer the NFT to `msg.sender`
    IERC721(erc721Rewards[_rewardId].nftContract).safeTransferFrom(
      address(this), 
      msg.sender,
      erc721Rewards[_rewardId].nftTokenId
    );

    emit ERC721Redeemed(msg.sender, erc721Rewards[_rewardId].nftContract, erc721Rewards[_rewardId].nftTokenId, _rewardId);
  }

  /// @dev Wraps ERC20 tokens as ERC1155 reward tokens.
  function wrapERC20(address _tokenContract, uint _tokenAmount, uint _numOfRewardsToMint, string calldata _rewardURI) external {

    require(
      IERC20(_tokenContract).balanceOf(msg.sender) >= _tokenAmount,
      "Rewards: Must own the amount of tokens that are being wrapped."
    );

    require(
      IERC20(_tokenContract).allowance(msg.sender, address(this)) >= _tokenAmount,
      "Rewards: Must approve this contract to transfer ERC20 tokens."
    );

    require(IERC20(_tokenContract).transferFrom(msg.sender, address(this), _tokenAmount), "Failed to transfer ERC20 tokens.");

    // Mint reward tokens to `msg.sender`
    _mint(msg.sender, nextTokenId, _numOfRewardsToMint, "");

    rewards[nextTokenId] = Reward({
      creator: msg.sender,
      uri: _rewardURI,
      supply: _numOfRewardsToMint,
      underlyingType: UnderlyingType.ERC20
    });

    erc20Rewards[nextTokenId] = ERC20Reward({
      tokenContract: _tokenContract,
      shares: _numOfRewardsToMint,
      underlyingTokenAmount: _tokenAmount
    });

    emit ERC20Rewards(msg.sender, _tokenContract, _tokenAmount, _numOfRewardsToMint, _rewardURI);
    
    nextTokenId++;    
  }

  /// @dev Lets the reward owner redeem their ERC20 tokens.
  function redeemERC20(uint _rewardId, uint _amount) external {
    require(balanceOf(msg.sender, _rewardId) >= _amount, "Rewards: Cannot redeem a reward you do not own.");
        
    // Burn the reward token
    _burn(msg.sender, _rewardId, _amount);

    // Get the ERC20 token amount to distribute
    uint amountToDistribute = (erc20Rewards[_rewardId].underlyingTokenAmount * _amount) / erc20Rewards[_rewardId].shares;

    // Transfer the ERC20 tokens to `msg.sender` 
    require(
      IERC20(erc20Rewards[_rewardId].tokenContract).transfer(msg.sender, amountToDistribute),
      "Rewards: Failed to transfer ERC20 tokens."
    );

    emit ERC20Redeemed(msg.sender, erc20Rewards[_rewardId].tokenContract, amountToDistribute, _amount);
  }

  /// @dev Updates a token's total supply.
  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  )
    internal
    override
  {
    super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

    // Decrease total supply if tokens are being burned.
    if (to == address(0)) {

      for(uint i = 0; i < ids.length; i++) {
        rewards[ids[i]].supply -= amounts[i];
      }
    }
  }

  /// @dev See EIP 1155
  function uri(uint _rewardId) public view override returns (string memory) {
    return rewards[_rewardId].uri;
  }

  /// @dev Returns the creator of reward token
  function creator(uint _rewardId) external view returns (address) {
    return rewards[_rewardId].creator;
  }
}