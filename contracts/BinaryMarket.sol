pragma solidity ^0.4.18;

contract BinaryPredictionMarket {
    address public oracle;
    uint public totalMarketStake;
    mapping (address => uint) public availableBalances;
    mapping (bool => Prediction) public predictions;
    bool public settled;
    bool public outcome;

    event Stake(address indexed _from, bool _prediction, uint _amount);
    event Deposit(address indexed _from, uint _amount);
    event Withdrawal(address indexed _to, uint _amount);
    event Claim(address indexed _to, bool _prediction, uint _amount);
    event Settled(bool _outcome);
    
    struct Prediction {
        mapping (address => uint) stakes;
        uint totalPredictionStake;
    }

    modifier afterSettled() {
        require(settled);
        _;
    }

    function BinaryPredictionMarket(address _oracle) public {
        oracle = _oracle;
        settled = false;
    }

    function () public payable {
        availableBalances[msg.sender] += msg.value;

        Deposit(msg.sender, msg.value);
    }

    function withdraw(uint withdrawal) public {
        if (withdrawal == 0 || availableBalances[msg.sender] == 0 || withdrawal > availableBalances[msg.sender]) {
            revert();
        }
        availableBalances[msg.sender] -= withdrawal;
        
        if (msg.sender.send(withdrawal)) {
            Withdrawal(msg.sender, withdrawal);
        }
    }

    function withdrawAll() public {
        uint withdrawal = availableBalances[msg.sender];

        if (withdrawal == 0) {
            revert();
        }

        availableBalances[msg.sender] = 0;
        
        if (msg.sender.send(withdrawal)) {
            Withdrawal(msg.sender, withdrawal);
        }
    }

    function choose(bool _outcome, uint _amount) public {
        if (msg.sender == oracle) {
            settle(_outcome);
        } else {
            predict(_outcome, _amount);
        }
    }

    function predict(bool _outcome, uint _amount) private {
        if (settled) {
            revert();
        }

        if (_amount == 0 || availableBalances[msg.sender] < _amount) {
            revert();
        }

        availableBalances[msg.sender] -= _amount;
        predictions[_outcome].stakes[msg.sender] += _amount;
        predictions[_outcome].totalPredictionStake += _amount;
        totalMarketStake += _amount;

        Stake(msg.sender, _outcome, _amount);
    }

    function settle(bool _outcome) private {
        if (settled) {
            revert();
        }

        if (totalMarketStake == 0) {
            revert();
        }
        
        outcome = _outcome;
        settled = true;

        Settled(_outcome);
    }

    function getStake(address predictor, bool prediction) public view returns (uint) {
        return predictions[prediction].stakes[predictor];
    }

    function getCorrectStake(address predictor) public view afterSettled returns (uint) {
        return predictions[outcome].stakes[predictor];
    }

    function claim() public afterSettled {
        uint userStake = getCorrectStake(msg.sender);
        if (userStake == 0) {
            revert();
        }

        uint reward = totalMarketStake*userStake / predictions[outcome].totalPredictionStake;

        predictions[outcome].stakes[msg.sender] = 0;

        availableBalances[msg.sender] += reward;

        Claim(msg.sender, outcome, reward);
    }
}