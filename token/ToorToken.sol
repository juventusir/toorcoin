pragma solidity ^0.4.18;


import "./ERC20Basic.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances.
 */
contract ToorToken is ERC20Basic, Ownable {
    using SafeMath for uint256;

    struct Account {
        uint balance;
        uint lastInterval;
    }

    mapping(address => Account) public accounts;
    mapping(uint256 => uint256) ratesByYear;
    mapping (address => mapping (address => uint256)) internal allowed;
    uint256 private rateMultiplier;

    uint256 initialSupply_;
    uint256 totalSupply_;
    uint256 public maxSupply;
    uint256 public startTime;
    uint256 pendingRewardsToMint;

    string public name;
    uint public decimals;
    string public symbol;

    uint256 private tokenGenInterval; // This defines the frequency at which we calculate rewards
    uint256 private vestingPeriod; // Defines how often tokens vest to team
    uint256 private cliff; // Defines the minimum amount of time required before tokens vest
    uint256 public pendingInstallments; // Defines the number of pending vesting installments for team
    uint256 public paidInstallments; // Defines the number of pending vesting installments for team
    uint256 private totalVestingPool; //  Defines total vesting pool set aside for team
    uint256 public pendingVestingPool; // Defines pending tokens in pool set aside for team
    uint256 public finalIntervalForTokenGen; // The last instance of reward calculation, after which rewards will cease
    uint256 private totalRateWindows; // This specifies the number of rate windows over the total period of time
    uint256 private intervalsPerWindow; // Total number of times we calculate rewards within 1 rate window

    // Variable to define once reward generation is complete
    bool public rewardGenerationComplete;

    // Ether addresses of founders and company
    mapping(uint256 => address) public distributionAddresses;

    // Events section
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function ToorToken() public {
        name = "ToorCoin";
        decimals = 18;
        symbol = "TOOR";

        // Setup the token staking reward percentage per year
        rateMultiplier = 10**14;
        ratesByYear[1] = 1.00474436026569 * 10**14;
        ratesByYear[2] = 1.00327808818412 * 10**14;
        ratesByYear[3] = 1.0027998411342 * 10**14;
        ratesByYear[4] = 1.00244353542177 * 10**14;
        ratesByYear[5] = 1.00216776307204 * 10**14;
        ratesByYear[6] = 1.0019479719906 * 10**14;
        ratesByYear[7] = 1.00176867594624 * 10**14;
        ratesByYear[8] = 1.00161962151688 * 10**14;
        ratesByYear[9] = 1.00149374903201 * 10**14;
        ratesByYear[10] = 1.00138603842211 * 10**14;
        ratesByYear[11] = 1.00129282200636 * 10**14;
        ratesByYear[12] = 1.00121135767832 * 10**14;
        ratesByYear[13] = 1.00113955418154 * 10**14;
        ratesByYear[14] = 1.00107578877672 * 10**14;
        ratesByYear[15] = 1.00101878296575 * 10**14;
        ratesByYear[16] = 1.00096751578846 * 10**14;
        ratesByYear[17] = 1.00092116207264 * 10**14;
        ratesByYear[18] = 1.00087904764088 * 10**14;
        ratesByYear[19] = 1.00084061627889 * 10**14;
        ratesByYear[20] = 1.00080540501263 * 10**14;

        totalRateWindows = 20;
        
        maxSupply = 100000000 * 10**18;
        initialSupply_ = 13500000 * 10**18;
        pendingInstallments = 7;
        paidInstallments = 0;
        totalVestingPool = 4500000 * 10**18;
        startTime = now;

        distributionAddresses[1] = 0xeD20cae0BF1FF4054E1a12bb071d41c95B5C94b5; // founder 1
        distributionAddresses[2] = 0x220Aad0b0bf12fF7245A29cbBA8fcfe72D0dE5d9; // founder 2
        distributionAddresses[3] = 0xc97dfb488407189C5b6d784678b6Dc8516Be88ca; // founder 3
        distributionAddresses[4] = 0x9fD5979af1B5048B05A0e5d8bf2362938C66c1c8; // founder 4
        distributionAddresses[5] = 0x91C3f66A7Bd302DEb55C2ffd0421D48F63DBE011; // founder 5
        distributionAddresses[6] = 0x14278b24e40138822aD75EC740c23e3a99300DBf; // company
        distributionAddresses[7] = 0x21445651dD395761544eF1658C5fFd2de7Ca45aC; // bounty
        
        // This is for 20 years
        // tokenGenInterval = 603936;  // This is roughly 1 week in seconds
        // uint256 timeToGenAllTokens = 628093440; // This is close to 20 years in seconds

        // This is for 5.7 hours
        tokenGenInterval = 60;
        uint256 timeToGenAllTokens = 62400;

        rewardGenerationComplete = false;
        
        // Mint initial tokens
        accounts[distributionAddresses[6]].balance = (initialSupply_ * 60) / 100; // 60% of initial balance goes to Company
        accounts[distributionAddresses[6]].lastInterval = 0;
        generateMintEvents(distributionAddresses[6],accounts[distributionAddresses[6]].balance);
        accounts[distributionAddresses[7]].balance = (initialSupply_ * 40) / 100; // 40% of inital balance goes to Bounty
        accounts[distributionAddresses[7]].lastInterval = 0;
        generateMintEvents(distributionAddresses[7],accounts[distributionAddresses[7]].balance);

        pendingVestingPool = totalVestingPool;
        pendingRewardsToMint = maxSupply - initialSupply_ - totalVestingPool;
        totalSupply_ = initialSupply_;
        vestingPeriod = timeToGenAllTokens / (totalRateWindows * 12); // One vesting period is a month
        cliff = vestingPeriod * 6; // Cliff is six vesting periods aka 6 months roughly
        finalIntervalForTokenGen = timeToGenAllTokens / tokenGenInterval;
        intervalsPerWindow = finalIntervalForTokenGen / totalRateWindows;
    }

    // This gives the total supply of actual minted coins. Does not take rewards pending minting into consideration
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    // This function is called directly by users who wish to transfer tokens
    function transfer(address _to, uint256 _value) canTransfer(_to) public returns (bool) {
        // Call underlying transfer method and pass in the sender address
        transferBasic(msg.sender, _to, _value);
        return true;
    }

    // This function is called by both transfer and transferFrom
    function transferBasic(address _from, address _to, uint256 _value) internal {
        uint256 tokensOwedSender = 0;
        uint256 tokensOwedReceiver = 0;
        uint256 balSender = balanceOfBasic(_from);

        // Distribute rewards tokens first
        if (!rewardGenerationComplete) {
            tokensOwedSender = tokensOwed(_from);
            require(_value <= (balSender.add(tokensOwedSender))); // Sender should have the number of tokens they want to send

            tokensOwedReceiver = tokensOwed(_to);

            // If there were tokens owed, increase total supply accordingly
            if ((tokensOwedSender.add(tokensOwedReceiver)) > 0) {
                increaseTotalSupply(tokensOwedSender.add(tokensOwedReceiver)); // This will break if total exceeds max cap
                pendingRewardsToMint = pendingRewardsToMint.sub(tokensOwedSender.add(tokensOwedReceiver));
            }

            // If there were tokens owed, raise mint events for them
            raiseEventIfMinted(_from, tokensOwedSender);
            raiseEventIfMinted(_to, tokensOwedReceiver);
        } else {
            require(_value <= balSender);
        }
        
        // Update balances of sender and receiver
        accounts[_from].balance = (balSender.add(tokensOwedSender)).sub(_value);
        accounts[_to].balance = (accounts[_to].balance.add(tokensOwedReceiver)).add(_value);

        // Update last intervals for sender and receiver
        uint256 currInt = intervalAtTime(now);
        accounts[_from].lastInterval = currInt;
        accounts[_to].lastInterval = currInt;

        emit Transfer(_from, _to, _value);
    }

    // This function allows someone to withdraw tokens from someone's address
    // For this to work, the person needs to have been approved by the account owner (via the approve function)
    function transferFrom(address _from, address _to, uint256 _value) canTransfer(_to) public returns (bool)
    {
        // Check that function caller has been approved to withdraw tokens
        require(_value <= allowed[_from][msg.sender]);

        // Call out base transfer method
        transferBasic(_from, _to, _value);

        // Subtract withdrawn tokens from allowance
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);

        return true;
    }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   *
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

      /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
    function allowance(address _owner, address _spender) public view returns (uint256)
    {
        return allowed[_owner][_spender];
    }

  
   // Increase the amount of tokens that an owner allowed to a spender.
   // approve should be called when allowed[_spender] == 0. To increment
   // allowed value is better to use this function to avoid 2 calls (and wait until the first transaction is mined)
    function increaseApproval(address _spender, uint _addedValue) public returns (bool)
    {
        allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(_addedValue);
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

   // Decrease the amount of tokens that an owner allowed to a spender.
   // approve should be called when allowed[_spender] == 0. To decrement
   // allowed value is better to use this function to avoid 2 calls (and wait until the first transaction is mined)
    function decreaseApproval(address _spender, uint _subtractedValue) public returns (bool)
    {
        uint oldValue = allowed[msg.sender][_spender];
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

    function raiseEventIfMinted(address owner, uint256 tokensToReward) private returns (bool) {
        if (tokensToReward > 0) {
            generateMintEvents(owner, tokensToReward);
        }
    }

    function addReward(address owner) private returns (bool) {
        uint256 tokensToReward = tokensOwed(owner);

        if (tokensToReward > 0) {
            increaseTotalSupply(tokensToReward); // This will break if total supply exceeds max cap. Should never happen though as tokensOwed checks for this condition
            accounts[owner].balance = accounts[owner].balance.add(tokensToReward);
            accounts[owner].lastInterval = intervalAtTime(now);
            pendingRewardsToMint = pendingRewardsToMint.sub(tokensToReward); // This helps track rounding errors when computing rewards
            generateMintEvents(owner, tokensToReward);
        }

        return true;
    }

    // This function is to vest tokens to the founding team
    function vestTokens() public returns (bool) {
        require(pendingInstallments > 0);
        require(paidInstallments < 7);
        require(pendingVestingPool > 0);
        require(now - startTime > cliff);

        // If they have rewards pending, allocate those first
        if (!rewardGenerationComplete) {
            for (uint256 i = 1; i <= 5; i++) {
                addReward(distributionAddresses[i]);
            }
        }

        uint256 currInterval = intervalAtTime(now);
        uint256 tokensToVest = 0;
        uint256 totalTokensToVest = 0;
        uint256 totalPool = totalVestingPool;

        uint256[2] memory founderCat;
        founderCat[0] = 0;
        founderCat[1] = 0;

        uint256[5] memory origFounderBal;
        origFounderBal[0] = accounts[distributionAddresses[1]].balance;
        origFounderBal[1] = accounts[distributionAddresses[2]].balance;
        origFounderBal[2] = accounts[distributionAddresses[3]].balance;
        origFounderBal[3] = accounts[distributionAddresses[4]].balance;
        origFounderBal[4] = accounts[distributionAddresses[5]].balance;

        uint256[2] memory rewardCat;
        rewardCat[0] = 0;
        rewardCat[1] = 0;

        // Pay out cliff
        if (paidInstallments < 1) {
            uint256 intervalAtCliff = intervalAtTime(cliff + startTime);
            tokensToVest = totalPool / 4;

            founderCat[0] = tokensToVest / 4;
            founderCat[1] = tokensToVest / 8;

            // This condition checks if there are any rewards to pay after the cliff
            if (currInterval > intervalAtCliff && !rewardGenerationComplete) {
                rewardCat[0] = tokensOwedByInterval(founderCat[0], intervalAtCliff, currInterval);
                rewardCat[1] = rewardCat[0] / 2;

                // Add rewards to founder tokens being vested
                founderCat[0] += rewardCat[0];
                founderCat[1] += rewardCat[1];

                // Increase total amount of tokens to vest
                tokensToVest += ((3 * rewardCat[0]) + (2 * rewardCat[1]));

                // Reduce pending rewards
                pendingRewardsToMint -= ((3 * rewardCat[0]) + (2 * rewardCat[1]));
            }

            // Vest tokens for each of the founders, this includes any rewards pending since cliff passed
            accounts[distributionAddresses[1]].balance += founderCat[0];
            accounts[distributionAddresses[2]].balance += founderCat[0];
            accounts[distributionAddresses[3]].balance += founderCat[0];
            accounts[distributionAddresses[4]].balance += founderCat[1];
            accounts[distributionAddresses[5]].balance += founderCat[1];

            totalTokensToVest = tokensToVest;

            // Update pending and paid installments
            pendingInstallments -= 1;
            paidInstallments += 1;
        }

        // Calculate the pending non-cliff installments to pay based on current time
        uint256 installments = ((currInterval * tokenGenInterval) - cliff) / vestingPeriod;
        uint256 installmentsToPay = installments + 1 - paidInstallments;

        // If there are no installments to pay, skip this
        if (installmentsToPay > 0) {
            if (installmentsToPay > pendingInstallments) {
                installmentsToPay = pendingInstallments;
            }

            // 12.5% vesting monthly after the cliff
            tokensToVest = (totalPool * 125) / 1000;

            founderCat[0] = tokensToVest / 4;
            founderCat[1] = tokensToVest / 8;

            uint256 intervalsAtVest = 0;

            // Loop through installments to pay, so that we can add token holding rewards as we go along
            for (uint256 installment = 1; installment <= installmentsToPay; installment++) {
                intervalsAtVest = intervalAtTime(cliff + (installment * vestingPeriod) + startTime);

                // This condition checks if there are any rewards to pay after the cliff
                if (currInterval >= intervalsAtVest && !rewardGenerationComplete) {
                    rewardCat[0] = tokensOwedByInterval(founderCat[0], intervalsAtVest, currInterval);
                    rewardCat[1] = rewardCat[0] / 2;

                    // Increase total amount of tokens to vest
                    totalTokensToVest += tokensToVest;
                    totalTokensToVest += ((3 * rewardCat[0]) + (2 * rewardCat[1]));

                    // Reduce pending rewards
                    pendingRewardsToMint -= ((3 * rewardCat[0]) + (2 * rewardCat[1]));

                    // Vest tokens for each of the founders, this includes any rewards pending since vest interval passed
                    accounts[distributionAddresses[1]].balance += (founderCat[0] + rewardCat[0]);
                    accounts[distributionAddresses[2]].balance += (founderCat[0] + rewardCat[0]);
                    accounts[distributionAddresses[3]].balance += (founderCat[0] + rewardCat[0]);
                    accounts[distributionAddresses[4]].balance += (founderCat[1] + rewardCat[1]);
                    accounts[distributionAddresses[5]].balance += (founderCat[1] + rewardCat[1]);
                }
            }

            pendingInstallments -= installmentsToPay;
            paidInstallments += installmentsToPay;
        }

        // Increase total supply by the number of tokens being vested
        increaseTotalSupply(totalTokensToVest);
            
        // Reduce pendingVestingPool and update pending and paid installments
        pendingVestingPool -= totalTokensToVest;

        accounts[distributionAddresses[1]].lastInterval = currInterval;
        accounts[distributionAddresses[2]].lastInterval = currInterval;
        accounts[distributionAddresses[3]].lastInterval = currInterval;
        accounts[distributionAddresses[4]].lastInterval = currInterval;
        accounts[distributionAddresses[5]].lastInterval = currInterval;

        // Create events for token generation
        generateMintEvents(distributionAddresses[1], (accounts[distributionAddresses[1]].balance - origFounderBal[0]));
        generateMintEvents(distributionAddresses[2], (accounts[distributionAddresses[2]].balance - origFounderBal[1]));
        generateMintEvents(distributionAddresses[3], (accounts[distributionAddresses[3]].balance - origFounderBal[2]));
        generateMintEvents(distributionAddresses[4], (accounts[distributionAddresses[4]].balance - origFounderBal[3]));
        generateMintEvents(distributionAddresses[5], (accounts[distributionAddresses[5]].balance - origFounderBal[4]));
    }

    function increaseTotalSupply (uint256 tokens) private returns (bool) {
        require ((totalSupply_.add(tokens)) <= maxSupply);
        totalSupply_ = totalSupply_.add(tokens);

        return true;
    }

    function tokensOwed(address owner) public view returns (uint256) {
        // This array is introduced to circumvent stack depth issues
        uint256 currInterval = intervalAtTime(now);
        uint256 lastInterval = accounts[owner].lastInterval;
        uint256 balance = accounts[owner].balance;

        return tokensOwedByInterval(balance, lastInterval, currInterval);
    }

    function tokensOwedByInterval(uint256 balance, uint256 lastInterval, uint256 currInterval) public view returns (uint256) {
        // Once the specified address has received all possible rewards, don't calculate anything
        if (lastInterval >= currInterval || lastInterval >= finalIntervalForTokenGen) {
            return 0;
        }

        uint256 tokensHeld = balance; //tokensHeld
        uint256 intPerWin = intervalsPerWindow;
        uint256 totalRateWinds = totalRateWindows;

        // Defines the number of intervals we compute rewards for at a time
        uint256 intPerBatch = 3; // Hardcoded here instead of storing on blockchain to save gas

        mapping(uint256 => uint256) ratByYear = ratesByYear;
        uint256 ratMultiplier = rateMultiplier;

        uint256 minRateWindow = (lastInterval / intPerWin).add(1);
        uint256 maxRateWindow = (currInterval / intPerWin).add(1);
        if (maxRateWindow > totalRateWinds) {
            maxRateWindow = totalRateWinds;
        }

        // Loop through pending periods of rewards, and calculate the total balance user should hold
        for (uint256 rateWindow = minRateWindow; rateWindow <= maxRateWindow; rateWindow++) {
            uint256 intervals = getIntervalsForWindow(rateWindow, lastInterval, currInterval, intPerWin);

            // This part is to ensure we don't overflow when rewards are pending for a large number of intervals
            // Loop through interval in batches
            while (intervals > 0) {
                if (intervals >= intPerBatch) {
                    tokensHeld = (tokensHeld.mul(ratByYear[rateWindow] ** intPerBatch)) / (ratMultiplier ** intPerBatch);
                    intervals = intervals.sub(intPerBatch);
                } else {
                    tokensHeld = (tokensHeld.mul(ratByYear[rateWindow] ** intervals)) / (ratMultiplier ** intervals);
                    intervals = 0;
                }
            }            
        }

        // Rewards owed are the total balance that user SHOULD have minus what they currently have
        return (tokensHeld.sub(balance));
    }

    function intervalAtTime(uint256 time) public view returns (uint256) {
        // Check to see that time passed in is not before contract generation time, as that would cause a negative value in the next step
        if (time <= startTime) {
            return 0;
        }

        // Based on time passed in, check how many intervals have elapsed
        uint256 interval = (time.sub(startTime)) / tokenGenInterval;
        uint256 finalInt = finalIntervalForTokenGen; // Assign to local to reduce gas
        
        // Return max intervals if it's greater than that time
        if (interval > finalInt) {
            return finalInt;
        } else {
            return interval;
        }
    }

    // This function checks how many intervals for a given window do we owe tokens to someone for 
    function getIntervalsForWindow(uint256 rateWindow, uint256 lastInterval, uint256 currInterval, uint256 intPerWind) public pure returns (uint256) {
        // If lastInterval for holder falls in a window previous to current one, the lastInterval for the window passed into the function would be the window start interval
        if (lastInterval < ((rateWindow.sub(1)).mul(intPerWind))) {
            lastInterval = ((rateWindow.sub(1)).mul(intPerWind));
        }

        // If currentInterval for holder falls in a window higher than current one, the currentInterval for the window passed into the function would be the window end interval
        if (currInterval > rateWindow.mul(intPerWind)) {
            currInterval = rateWindow.mul(intPerWind);
        }

        return currInterval.sub(lastInterval);
    }

    // This function tells the balance of tokens at a particular address
    function balanceOf(address _owner) public view returns (uint256 balance) {
        if (rewardGenerationComplete) {
            return accounts[_owner].balance;
        } else {
            return (accounts[_owner].balance).add(tokensOwed(_owner));
        }
    }

    function balanceOfBasic(address _owner) public view returns (uint256 balance) {
        return accounts[_owner].balance;
    }

    // This functions returns the last time at which rewards were transferred to a particular address
    function lastTimeOf(address _owner) public view returns (uint256 interval, uint256 time) {
        return (accounts[_owner].lastInterval, ((accounts[_owner].lastInterval).mul(tokenGenInterval)).add(startTime));
    }

    // This function is not meant to be used. It's only written as a fail-safe against potential unforeseen issues
    function mint(address _to, uint256 _amount) onlyOwner public returns (bool) {
        increaseTotalSupply(_amount);
        accounts[_to].balance = (accounts[_to].balance).add(_amount);
        generateMintEvents(_to, _amount);
        return true;
    }

    function generateMintEvents(address _to, uint256 _amount) private returns (bool) {
        emit Mint(_to, _amount);
        emit Transfer(address(0), _to, _amount);

        return true;
    }

    // Allows the burning of tokens
    function burn(uint256 _value) public {
        require(_value <= balanceOf(msg.sender));

        // First add any rewards pending for the person burning tokens
        addReward(msg.sender);

        // Update balance and lastInterval of person burning tokens
        accounts[msg.sender].balance = (accounts[msg.sender].balance).sub(_value);
        accounts[msg.sender].lastInterval = intervalAtTime(now);

        // Update total supply
        totalSupply_ = totalSupply_.sub(_value);

        // Raise events
        emit Burn(msg.sender, _value);
        emit Transfer(msg.sender, address(0), _value);
    }

    // These set of functions allow changing of founder and company addresses
    function setFounder(uint256 id, address _to) onlyOwner public returns (bool) {
        require(_to != address(0));
        distributionAddresses[id] = _to;
        return true;
    }

    // This is a setter for rewardGenerationComplete. It will be used to see if token rewards need to be computed, and can only be set by owner
    function setRewardGenerationComplete(bool _value) onlyOwner public returns (bool) {
        rewardGenerationComplete = _value;
        return true;
    }

    // This function is added to get a state of where the token is in term of reward generation
    function getNow() public view returns (uint256, uint256) {
        return (now, block.number);
    }

    // This modifier is used on the transfer method and defines where tokens CANNOT be sent
    modifier canTransfer(address _to) {
        require(_to != address(0)); // Transfer should not be allowed to burn tokens
        _;
    }
}