interface IWETH {
    function deposit() external payable;
    function balanceOf(address owner) external payable returns(uint256);
}