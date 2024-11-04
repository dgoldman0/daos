// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// DataManager contract: Responsible for managing the core details of tasks, such as creation, assignment, and completion.
// This contract is intended to serve as the main storage of all task data, allowing only the Project contract to interact with tasks by ID.
contract DataManager is AccessControl {
    // Role definitions for access control
    bytes32 public constant PROJECT_ROLE = keccak256("PROJECT_ROLE");
    
    // Struct to store task details, which includes basic task attributes like name, dates, and assigned person.
    struct Task {
        uint id; // Unique identifier for the task to maintain task distinction.
        string name; // Name of the task to provide context to its purpose.
        uint startDate; // UNIX timestamp indicating when the task is scheduled to begin.
        uint endDate; // UNIX timestamp indicating the deadline for the task.
        bool isComplete; // Flag indicating if the task is complete, used for tracking progress.
        address assignedTo; // Ethereum address representing the individual responsible for the task.
        uint[] dependencies; // List of task IDs that need to be completed before this task, ensuring proper sequencing of tasks.
    }

    uint public taskCount = 0; // Counter to keep track of the total number of tasks created, used to generate unique task IDs.
    mapping(uint => Task) public tasks; // Mapping to store tasks by their unique ID, allowing efficient access to task details.

    // Events to provide visibility into task lifecycle changes.
    event TaskCreated(uint id, string name, uint startDate, uint endDate, address assignedTo, uint[] dependencies);
    event TaskCompleted(uint id);
    event TaskReassigned(uint id, address newAssignee);

    // Constructor to set up roles
    constructor(address projectAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // Grant admin role to the deployer
        _setupRole(PROJECT_ROLE, projectAddress); // Grant PROJECT_ROLE to the Project contract
    }

    // Modifier to check if the caller has the PROJECT_ROLE
    modifier onlyProject() {
        require(hasRole(PROJECT_ROLE, msg.sender), "Caller is not authorized");
        _;
    }

    // Function to create a new task with dependencies and assign it to an address.
    // Only the Project contract can create new tasks.
    function createTask(
        string memory _name, // Name to describe the purpose of the task.
        uint _startDate, // Start date timestamp.
        uint _endDate, // End date timestamp, representing the deadline.
        address _assignedTo, // Ethereum address responsible for completing the task.
        uint[] memory _dependencies // Array of task IDs that must be completed before this task.
    ) public onlyProject {
        require(_startDate < _endDate, "Start date must be before end date"); // Validation to ensure deadlines are logical.
        
        // Ensure that all dependencies refer to existing tasks, maintaining data integrity.
        for (uint i = 0; i < _dependencies.length; i++) {
            require(_dependencies[i] < taskCount, "Dependency does not exist");
        }
        
        // Create and store the new task in the mapping.
        tasks[taskCount] = Task(
            taskCount,
            _name,
            _startDate,
            _endDate,
            false,
            _assignedTo,
            _dependencies
        );
        
        emit TaskCreated(taskCount, _name, _startDate, _endDate, _assignedTo, _dependencies); // Emit an event to signal that a new task has been created.
        taskCount++; // Increment the task counter to maintain unique IDs.
    }

    // Function to mark a task as complete.
    // A task can only be marked complete if all its dependencies have been completed, ensuring proper workflow.
    function completeTask(uint taskId) public onlyProject {
        Task storage task = tasks[taskId]; // Retrieve the task to modify it.
        require(!task.isComplete, "Task is already complete"); // Ensure that the task is not already completed.
        
        // Verify that all dependencies have been completed before marking this task as complete.
        for (uint i = 0; i < task.dependencies.length; i++) {
            require(tasks[task.dependencies[i]].isComplete, "All dependencies must be completed before this task");
        }

        task.isComplete = true; // Update the task's status to complete.
        emit TaskCompleted(taskId); // Emit an event to signal that the task has been completed.
    }

    // Function to reassign a task to a different address.
    // Only the Project contract can reassign tasks.
    function reassignTask(uint taskId, address newAssignee) public onlyProject {
        Task storage task = tasks[taskId]; // Retrieve the task to modify it.
        task.assignedTo = newAssignee; // Update the assignee.
        emit TaskReassigned(taskId, newAssignee); // Emit an event to signal that the task has been reassigned.
    }

    // Function to get details about a task by ID.
    // This provides visibility into a task's status, dependencies, and assignment for both on-chain and off-chain interactions.
    function getTask(uint taskId) public view returns (
        uint, string memory, uint, uint, bool, address, uint[] memory
    ) {
        Task storage task = tasks[taskId]; // Retrieve the task from storage.
        return (task.id, task.name, task.startDate, task.endDate, task.isComplete, task.assignedTo, task.dependencies); // Return the task details.
    }
}

// MetaDataManager contract: Manages auxiliary data for tasks, such as priority, labels, and comments.
// This data is separated from core task data to allow for more flexibility and modularity in task management.
contract MetaDataManager is AccessControl {
    // Role definitions for access control
    bytes32 public constant PROJECT_ROLE = keccak256("PROJECT_ROLE");
    
    // Struct to store additional metadata for tasks, enhancing task tracking and collaboration capabilities.
    struct MetaData {
        uint taskId; // ID of the associated task.
        uint8 priority; // Priority level of the task (0 = Low, 1 = Medium, 2 = High).
        string[] labels; // Labels or categories to categorize tasks and facilitate filtering.
        uint8 progress; // Progress percentage, allowing for partial completion tracking.
        string[] comments; // Array of comments for team collaboration and communication.
    }

    mapping(uint => MetaData) public metaDatas; // Mapping of task IDs to their metadata for easy lookup.

    // Events to provide visibility into metadata changes, such as priority updates or new comments.
    event MetaDataUpdated(uint taskId, uint8 priority, string[] labels, uint8 progress);
    event CommentAdded(uint taskId, string comment);

    // Constructor to set up roles
    constructor(address projectAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // Grant admin role to the deployer
        _setupRole(PROJECT_ROLE, projectAddress); // Grant PROJECT_ROLE to the Project contract
    }

    // Modifier to check if the caller has the PROJECT_ROLE
    modifier onlyProject() {
        require(hasRole(PROJECT_ROLE, msg.sender), "Caller is not authorized");
        _;
    }

    // Function to update metadata for a task.
    // Only the Project contract can update metadata, ensuring data integrity.
    function updateMetaData(uint taskId, uint8 _priority, string[] memory _labels, uint8 _progress) public onlyProject {
        MetaData storage metaData = metaDatas[taskId]; // Retrieve the metadata to modify it.
        metaData.priority = _priority; // Update priority.
        metaData.labels = _labels; // Update task labels.
        metaData.progress = _progress; // Update progress percentage.

        emit MetaDataUpdated(taskId, _priority, _labels, _progress); // Emit an event to signal that metadata has been updated.
    }

    // Function to add a comment to a task.
    // Only the Project contract can add comments, ensuring controlled access.
    function addComment(uint taskId, string memory comment) public onlyProject {
        MetaData storage metaData = metaDatas[taskId]; // Retrieve the metadata to modify it.
        metaData.comments.push(comment); // Append the new comment to the list of comments.

        emit CommentAdded(taskId, comment); // Emit an event to signal that a comment has been added.
    }

    // Function to retrieve metadata for a specific task.
    // This provides detailed insights into the task's progress, labels, and collaboration status.
    function getMetaData(uint taskId) public view returns (
        uint8, string[] memory, uint8, string[] memory
    ) {
        MetaData storage metaData = metaDatas[taskId]; // Retrieve metadata from storage.
        return (metaData.priority, metaData.labels, metaData.progress, metaData.comments); // Return all metadata details.
    }
}

// Project contract: Manages the interaction between the DataManager and MetaDataManager contracts.
// It acts as a facade that provides a simplified interface for managing both core tasks and their metadata.
contract Project is Ownable {
    DataManager public dataManager; // Instance of DataManager contract to manage core task details.
    MetaDataManager public metaDataManager; // Instance of MetaDataManager contract to manage additional task metadata.

    // Constructor to initialize the Project contract with addresses for DataManager and MetaDataManager.
    // This allows for flexibility in deploying and managing multiple projects independently.
    constructor(address dataManagerAddress, address metaDataManagerAddress) {
        dataManager = DataManager(dataManagerAddress); // Set the DataManager contract address.
        metaDataManager = MetaDataManager(metaDataManagerAddress); // Set the MetaDataManager contract address.
    }

    // Modifier to ensure that a task exists before interacting with it.
    // Prevents errors by validating the task ID before proceeding with function logic.
    modifier taskExists(uint taskId) {
        require(taskId < dataManager.taskCount(), "Task does not exist"); // Validate that the task ID is within the valid range.
        _;
    }

    // Function to create a new task, delegating the logic to the DataManager contract.
    // This keeps the Project contract focused on providing a unified interface.
    function createTask(
        string memory _name, // Name to identify the task.
        uint _startDate, // Timestamp for the task start date.
        uint _endDate, // Timestamp for the task deadline.
        address _assignedTo, // Address responsible for completing the task.
        uint[] memory _dependencies // Array of dependent task IDs.
    ) public onlyOwner {
        dataManager.createTask(_name, _startDate, _endDate, _assignedTo, _dependencies); // Delegate task creation.
    }

    // Function to mark a task as complete.
    // Ensures that only the assigned user or the owner can complete their task, and verifies task existence.
    function completeTask(uint taskId) public taskExists(taskId) {
        (, , , , , address assignedTo, ) = dataManager.getTask(taskId); // Retrieve the task details.
        require(msg.sender == assignedTo || msg.sender == owner(), "Only the assignee or owner can mark as complete"); // Ensure only assignee or owner can complete.
        dataManager.completeTask(taskId); // Delegate completion to DataManager.
    }

    // Function to reassign a task to a new address.
    // Ensures only the current assignee or the owner can initiate a reassignment, maintaining accountability.
    function reassignTask(uint taskId, address newAssignee) public taskExists(taskId) {
        (, , , , , address assignedTo, ) = dataManager.getTask(taskId); // Retrieve the task details.
        require(msg.sender == assignedTo || msg.sender == owner(), "Only the current assignee or owner can reassign"); // Ensure only assignee or owner can reassign.
        dataManager.reassignTask(taskId, newAssignee); // Delegate reassignment to DataManager.
    }

    // Function to update metadata for a task, delegating to MetaDataManager.
    // This function allows updating non-core data such as priority, labels, or progress.
    function updateMetaData(uint taskId, uint8 _priority, string[] memory _labels, uint8 _progress) public onlyOwner taskExists(taskId) {
        metaDataManager.updateMetaData(taskId, _priority, _labels, _progress); // Delegate metadata update.
    }

    // Function to add a comment to a task, facilitating team communication.
    // Comments can help provide clarification, feedback, or updates for a task.
    function addComment(uint taskId, string memory comment) public taskExists(taskId) {
        metaDataManager.addComment(taskId, comment); // Delegate adding a comment to MetaDataManager.
    }

    // Function to get core task details by ID.
    // This provides access to task-specific data such as deadlines, dependencies, and assignments.
    function getTask(uint taskId) public view taskExists(taskId) returns (
        uint, string memory, uint, uint, bool, address, uint[] memory
    ) {
        return dataManager.getTask(taskId); // Retrieve task details from DataManager.
    }

    // Function to get metadata for a task by ID.
    // Allows access to additional information like priority, progress, and comments for better tracking.
    function getMetaData(uint taskId) public view taskExists(taskId) returns (
        uint8, string[] memory, uint8, string[] memory
    ) {
        return metaDataManager.getMetaData(taskId); // Retrieve metadata details from MetaDataManager.
    }
}
