pragma solidity ^0.4.18;

contract PredictionMarket {
    address public oracle;
    uint public totalMarketStake;
    mapping (address => uint) public availableBalances;
    mapping (bytes32 => Prediction) public predictions;
    bool public settled;
    bytes32 public outcome;

    event Stake(address indexed _from, bytes32 _prediction, uint _amount);
    event Deposit(address indexed _from, uint _amount);
    event Withdrawal(address indexed _to, uint _amount);
    event Claim(address indexed _to, bytes32 _prediction, uint _amount);
    event Settled(bytes32 _outcome);
    
    struct Prediction {
        mapping (address => uint) stakes;
        uint totalPredictionStake;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle);
        _;
    }

    modifier afterSettled() {
        require(settled);
        _;
    }

    function PredictionMarket(address _oracle) public {
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

    function predict(bytes32 prediction, uint amount) public {
        if (settled) {
            revert();
        }

        if (amount == 0 || availableBalances[msg.sender] < amount) {
            revert();
        }

        availableBalances[msg.sender] -= amount;
        predictions[prediction].stakes[msg.sender] += amount;
        predictions[prediction].totalPredictionStake += amount;
        totalMarketStake += amount;

        Stake(msg.sender, prediction, amount);
    }

    function settle(bytes32 _outcome) public onlyOracle {
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

    function getStake(address predictor, bytes32 prediction) public view returns (uint) {
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