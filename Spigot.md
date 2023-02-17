## Features 
- Trustlessly secure DAO revenue streams for lenders
- Automatically pay back debt for borrowers
- Easily configurable to handle any contract without writing custom code
- Handles push and pull payments from revenue contracts


## Security Considerations
In order to actually secure the revenue stream, the Lender must know that the address that revenue gets sent to can't be changed. This is why the Spigot must directly own revenue generating contracts.

The Borrower must still operate their product so the Lender can allow specific functions on revenue generating contracts (that don't change contract owner) to ensure revenue keeps flowing. On the other side, the Borrower doesn't want the Lender to fuck up their product so the owner can only call the function on revenue generating contracts to revert control to Borrowers.

At the moment there is potential for griefing if the Lender decides to not revert ownership of revenue generating contracts to the Borrower. However the Spigot will be owned by the Loan contract, not an EOA, which will automatically release revenue contracts once the Borrower has fully repaid their loan.

Can use operate() to claim ownership of contracts that require confirmation after transferring owernship.

## Potential Code Optimizations
- Compacting `whitelistedFunctions` into an encoded uint256 var instead of a mapping to bool.
- Use proxy pattern for SpigotController as implementation contract and proxy contracts for each borrower. Or make library 
