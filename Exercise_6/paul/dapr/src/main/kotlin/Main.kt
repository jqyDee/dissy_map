import com.fasterxml.jackson.databind.ObjectMapper
import io.dapr.client.DaprClient
import io.dapr.client.DaprClientBuilder
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.request.receiveText
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.random.Random

val json = ObjectMapper()

const val PUBSUB = "pubsub"
const val STORE = "statestore"

fun main(args: Array<String>){

    //parse command line arguments --role --port (--id for workers) into config
    // "--role=worker --id=2 --port=8082"  ->  {role=worker, id=2, port=8082}

    val config = args.associate {
            val (k, v) = it.removePrefix("--").split("=", limit = 2)
            k to v
        }

    val role = config["role"] ?: error("Usage --role=coordinator or --role=worker")
    val port = config["port"]?.toInt() ?: 8080

    //requirement 1: initializing 1 coordinator and 3 workers, either manually through terminals or yaml file
    when (role) {
        "coordinator" -> runCoordinator(port)
        "worker" -> {
            val id = config["id"] ?: error("Usage --id=1..3")
            runWorker("Worker $id", port)
        }
        else -> error("Unknown role $role")
    }
}

fun runCoordinator(port: Int): Unit {
    val dapr = DaprClientBuilder().build()
    dapr.waitForSidecar(10_000).block() // wait 10 seconds until sidecar is reachable

    // requirement 4: execution state of each job is in coordinators data scope, CoordinatorState contains list of jobs, which hold their execution state
    // state is saved to dapr state store below and also in fun assignPendingJobs
    val state = CoordinatorState()

    //requirement 2: submitting 6 jobs with unique identifiers Job 1 to Job 6
    for (i in 1..6) state.jobs.add(Job("Job $i"))
    dapr.saveState(STORE, "coordinator", state).block()
    println("Coordinator initialized")

    val lock = Mutex()

    embeddedServer(Netty, port = port) {
        routing {
            get("/dapr/subscribe") {
                call.respondText(
                    """[
                        {"pubsubname":"pubsub","topic":"worker-ready","route":"/worker-ready"},
                        {"pubsubname":"pubsub","topic":"job-completed","route":"/job-completed"}
                    ]""",
                    ContentType.Application.Json,
                )
            }
            post("/worker-ready") {
                val event = readEvent(call.receiveText())
                lock.withLock {
                    state.workers[event.workerId] = WorkerState.AVAILABLE

                    // Wait until all 3 workers exist, then do the first assignment round
                    // requirement 3 inside fun assignPendingJobs
                    if (state.workers.size == 3) {
                        assignPendingJobs(state, dapr)
                        //requirement 5: log pending jobs as pending
                        state.jobs.filter { it.state == JobState.PENDING }
                            .forEach { println("${it.id} pending") }
                    }
                }
                call.respond(HttpStatusCode.OK)
            }
            post("/job-completed") {
                val event = readEvent(call.receiveText())
                lock.withLock {
                    println("${event.workerId} completed ${event.jobId}")
                    //requirement 7: upon completion of a job set job state to COMPLETED and worker state to AVAILABLE
                    state.jobs.first { it.id == event.jobId }.state = JobState.COMPLETED
                    state.workers[event.workerId] = WorkerState.AVAILABLE
                    //requirement 8: assign pending jobs when a worker becomes available
                    assignPendingJobs(state, dapr)
                    //requirement 10: print notification once all jobs have been completed
                    if (state.jobs.all { it.state == JobState.COMPLETED }) println("All jobs completed")
                }
                call.respond(HttpStatusCode.OK)
            }
        }
    }.start(wait = true)
}

fun runWorker(name: String, port: Int) {
    val dapr = DaprClientBuilder().build()

    embeddedServer(Netty, port = port) {
        routing {
            get("/dapr/subscribe") {
                call.respondText(
                    "[{\"pubsubname\":\"pubsub\",\"topic\":\"job-assigned\",\"route\":\"/job-assigned\"}]",
                    ContentType.Application.Json,
                )
            }
            post("/job-assigned") {
                val event = readEvent(call.receiveText())
                if (event.workerId == name) {
                    //requirement 6: simulating work load via delay between 500 and 1500 ms and notifying coordinator via publishEvent to "job-completed"
                    delay(Random.nextLong(500, 1500))
                    dapr.publishEvent(PUBSUB, "job-completed", event).block()
                }
                call.respond(HttpStatusCode.OK)
            }
        }
    }.start(wait = false)

    dapr.waitForSidecar(10_000).block()
    println("$name initialized")
    dapr.publishEvent(PUBSUB, "worker-ready", JobEvent(workerId = name)).block()

    Thread.currentThread().join()
}

fun readEvent(body: String): JobEvent {
    val data = json.readTree(body)["data"]
    return JobEvent(data["jobId"].asText(), data["workerId"].asText())
}

fun assignPendingJobs(state: CoordinatorState, dapr: DaprClient) {
    //requirement 3: assign jobs only to available workers, FIFO order for pending jobs
    for (job in state.jobs.filter { it.state == JobState.PENDING }) {
        val freeWorker = state.workers.entries
            .firstOrNull { it.value == WorkerState.AVAILABLE }
            ?.key
            ?: break //requirement 5: after assigning first pending job we have a break -> other pending jobs stay pending

        // requirement 9: after being assigned a job worker state is set to BUSY -> workers process at most one job at a time
        job.state = JobState.RUNNING
        state.workers[freeWorker] = WorkerState.BUSY
        println("${job.id} assigned to $freeWorker")
        dapr.publishEvent(PUBSUB, "job-assigned", JobEvent(job.id, freeWorker)).block()
    }
    dapr.saveState(STORE, "coordinator", state).block()
}