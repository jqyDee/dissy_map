# EX05 Report: [Fault Tolerance & Coordination]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  
**Group Name:** `MAP`

---

## Task 1 - [Distributed Auction]

In this exercise we are supposed to implement a distributed auction that allows
participants to submit bids through different application nodes. The application
has to support __Placing a bid__, __Querying the auction__ and __Closing the
auction__. The nodes have to use Zookeeper and be run on different machines. 

To check the functionality, we are tasked to start five application node on
different machines, submit bids through the nodes and verify that they observe
the same atuction state after the updates have completed.


