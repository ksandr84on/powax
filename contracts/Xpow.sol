// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;


// Mineable ERC20 Token using Proof Of Work

// XPOW token


abstract contract ERC20Interface {

    function totalSupply() external virtual view returns (uint);

    function balanceOf(address tokenOwner) external virtual view returns (uint balance);

    function allowance(address tokenOwner, address spender) external virtual view returns (uint remaining);

    function transfer(address to, uint tokens) external virtual returns (bool success);

    function approve(address spender, uint tokens) external virtual returns (bool success);

    function transferFrom(address from, address to, uint tokens) external virtual returns (bool success);

    function _approve(address owner, address spender, uint tokens) internal virtual returns (bool success);

    function _transfer(address from, address to, uint tokens) internal virtual returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);

    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

}

contract ERC20Standard is ERC20Interface {

    string public symbol;
    string public name;

    uint8 public decimals;

    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;

    uint public override totalSupply;

    constructor(string memory _symbol, string memory _name, uint8 _decimals){
        symbol = _symbol;
        name = _name;
        decimals = _decimals;
    }

    function _transfer(address from, address to, uint tokens) internal override returns (bool success) {

        balances[from] = balances[from] - (tokens);

        balances[to] = balances[to] + (tokens);

        emit Transfer(from, to, tokens);

        return true;
    }

    function balanceOf(address tokenOwner) public override view returns (uint balance) {

        return balances[tokenOwner];

    }

    function transfer(address to, uint tokens) public override returns (bool success) {

        return _transfer(msg.sender, to, tokens);

    }

    function approve(address spender, uint tokens) public override returns (bool success) {

        return _approve(msg.sender, spender,tokens);

    }

    function _approve(address owner, address spender, uint tokens) internal override returns (bool success) {

        allowed[owner][spender] = tokens;

        emit Approval(owner, spender, tokens);

        return true;

    }

    function transferFrom(address from, address to, uint tokens) public override returns (bool success) {

        allowed[from][msg.sender] = allowed[from][msg.sender] - (tokens);

        return _transfer(from,to,tokens);

    }

    function allowance(address tokenOwner, address spender) public override view returns (uint remaining) {

        return allowed[tokenOwner][spender];

    }


}

library SafeMath {

    function add(uint a, uint b) internal pure returns (uint c) {

        c = a + b;

        require(c >= a);

    }

    function sub(uint a, uint b) internal pure returns (uint c) {

        require(b <= a);

        c = a - b;

    }

    function mul(uint a, uint b) internal pure returns (uint c) {

        c = a * b;

        require(a == 0 || c / a == b);

    }

    function div(uint a, uint b) internal pure returns (uint c) {

        require(b > 0);

        c = a / b;

    }

}


library ExtendedMath {


    //return the smaller of the two inputs (a or b)
    function limitLessThan(uint a, uint b) internal pure returns (uint c) {

        if(a > b) return b;

        return a;

    }
}



contract Xpow is ERC20Standard("POWAX","Avax POW Token",8) {

    using SafeMath for uint;
    using ExtendedMath for uint;

    uint public latestDifficultyPeriodStarted;

    uint public epochCount;

    uint public _BLOCKS_PER_READJUSTMENT = 1024;
    uint public  _MINIMUM_TARGET = 2**16;
    uint public  _MAXIMUM_TARGET = 2**234;


    uint public miningTarget;
    bytes32 public challengeNumber;

    uint public rewardEra;
    uint public maxSupplyForEra;

    uint public currentMiningReward;
    address public lastRewardTo;
    uint public lastRewardAmount;
    uint public lastRewardEthBlockNumber;

    uint public tokensMinted;

    event Mint(address from, uint reward_amount, uint epochCount, bytes32 newChallengeNumber);


    constructor() {

      totalSupply = 21000000 * 10**uint(decimals);

      tokensMinted = 0;

      rewardEra = 0;
      maxSupplyForEra = totalSupply.div(2);
      currentMiningReward = 10 * 10**uint(decimals);


      miningTarget = _MAXIMUM_TARGET;

      latestDifficultyPeriodStarted = block.number;

       _startNewMiningEpoch();

    }


    function mint(uint256 nonce, bytes32) public returns (bool success) {

        return mintTo(nonce,msg.sender);

    }

    function mintTo(uint256 nonce, address minter) public returns (bool success) {

        //the PoW must contain work that includes a recent ethereum block hash (challenge number) and the msg.sender's address to prevent MITM attacks
        bytes32 digest = keccak256(abi.encodePacked(challengeNumber, minter, nonce ));

        //the digest must be smaller than the target
        if(uint256(digest) > miningTarget) revert();

        //only allow one reward for each block
        require(lastRewardEthBlockNumber != block.number);

        balances[minter] = balances[minter] + (currentMiningReward);
        emit Transfer(address(this), minter, currentMiningReward);

        tokensMinted = tokensMinted + currentMiningReward;

        //Cannot mint more tokens than there are
        require(tokensMinted <= maxSupplyForEra);

        //set readonly diagnostics data
        lastRewardTo = minter;
        lastRewardAmount = currentMiningReward;
        lastRewardEthBlockNumber = block.number;

        _startNewMiningEpoch();

        emit Mint(minter, currentMiningReward, epochCount, challengeNumber );

        return true;

    }



    function _startNewMiningEpoch() internal {

      //if max supply for the era will be exceeded next reward round then enter the new era before that happens

      //32 is the final reward era, almost all tokens minted
      //once the final era is reached, more tokens will not be given out because the assert function
      if(tokensMinted + (currentMiningReward) > maxSupplyForEra && rewardEra < 31)
      {
        rewardEra = rewardEra + 1;
        currentMiningReward = (10 * 10**uint(decimals)).div( 2**rewardEra ) ;
      }

      //set the next minted supply at which the era will change
      //total supply is 2100000000000000  because of 8 decimal places
      maxSupplyForEra = totalSupply - (totalSupply.div( 2**(rewardEra + 1)));

      epochCount = epochCount + 1;

      //every so often, readjust difficulty. Dont readjust when deploying
      if(epochCount % _BLOCKS_PER_READJUSTMENT == 0)
      {
        uint ethBlocksSinceLastDifficultyPeriod = block.number - latestDifficultyPeriodStarted;

        _reAdjustDifficulty(ethBlocksSinceLastDifficultyPeriod);
      }


      //make the latest ethereum block hash a part of the next challenge for PoW to prevent pre-mining future blocks
     challengeNumber = blockhash(block.number - 1);

    }



    function _reAdjustDifficulty(uint ethBlocksSinceLastDifficultyPeriod) internal {


        uint targetEthBlocksPerDiffPeriod = _BLOCKS_PER_READJUSTMENT * 60;

        //if there were less eth blocks passed in time than expected
        if( ethBlocksSinceLastDifficultyPeriod < targetEthBlocksPerDiffPeriod )
        {
          uint excess_block_pct = (targetEthBlocksPerDiffPeriod * (100)) / ( ethBlocksSinceLastDifficultyPeriod );

          uint excess_block_pct_extra = (excess_block_pct - 100).limitLessThan(1000);
          // If there were 5% more blocks mined than expected then this is 5.  If there were 100% more blocks mined than expected then this is 100.

          //make it harder
          miningTarget = miningTarget - ((miningTarget / 2000) * excess_block_pct_extra);   //by up to 50 %
        }else{
          uint shortage_block_pct = (ethBlocksSinceLastDifficultyPeriod * (100)) / ( targetEthBlocksPerDiffPeriod );

          uint shortage_block_pct_extra = (shortage_block_pct - 100).limitLessThan(1000); //always between 0 and 1000

          //make it easier
          miningTarget = miningTarget + ((miningTarget / 2000) * shortage_block_pct_extra);   //by up to 50 %
        }


        latestDifficultyPeriodStarted = block.number;

        if(miningTarget < _MINIMUM_TARGET) //most difficult
        {
          miningTarget = _MINIMUM_TARGET;
        }

        if(miningTarget > _MAXIMUM_TARGET) //most easy
        {
          miningTarget = _MAXIMUM_TARGET;
        }
    }



    function getChallengeNumber() public view returns (bytes32) {
        return challengeNumber;
    }

    //the number of zeroes the digest of the PoW solution requires.  Auto adjusts
     function getMiningDifficulty() public view returns (uint) {
        return _MAXIMUM_TARGET / (miningTarget);
    }

    function getMiningTarget() public view returns (uint) {
       return miningTarget;
    }


    function minedSupply() public view returns (uint) {

        return tokensMinted;

    }

    receive() external payable virtual {

        revert();

    }

}
