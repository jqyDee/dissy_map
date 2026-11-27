enum class JobState { PENDING, RUNNING, COMPLETED }
enum class WorkerState { AVAILABLE, BUSY }

data class Job(
    val id: String = "",
    var state: JobState = JobState.PENDING,
)

data class CoordinatorState(
    val jobs: MutableList<Job> = mutableListOf(),
    var workers: MutableMap<String, WorkerState> = mutableMapOf(),
)

data class JobEvent(
    val jobId: String = "",
    val workerId: String = "",
)