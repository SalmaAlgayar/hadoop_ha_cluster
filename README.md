# Hadoop High Availability Cluster

![NameNode (1920 x 1200 px)](https://github.com/user-attachments/assets/458f9572-1beb-47d5-a172-85f029e28d40)


A fully containerized Hadoop cluster with automatic failover, built using Docker. Eliminates single points of failure through Quorum Journal Manager (QJM) and ZooKeeper-based NameNode HA.

---

## Architecture

The cluster spans **5 nodes** divided into a control plane and a data plane.

```
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────┐
│       master1       │   │     zk_journal      │   │     master2     │
│                     │   │                     │   │                 │
│  NameNode (Active)  │   │  QuorumPeerMain     │   │  NameNode       │
│  ResourceManager    │   │  JournalNode        │   │  (Standby)      │
│  DESZKFailover-     │   │                     │   │  ResourceManager│
│    Controller       │   │                     │   │  DESZKFailover- │
│  QuorumPeerMain     │   │                     │   │    Controller   │
│  JournalNode        │   │                     │   │  QuorumPeerMain │
│                     │   │                     │   │  JournalNode    │
└─────────────────────┘   └─────────────────────┘   └─────────────────┘

              ┌─────────────────────┐   ┌─────────────────────┐
              │       worker1       │   │       worker2       │
              │                     │   │                     │
              │  DataNode           │   │  DataNode           │
              │  NodeManager        │   │  NodeManager        │
              └─────────────────────┘   └─────────────────────┘
```

### Component Reference

| Component | Role |
|---|---|
| **NameNode (NN)** | HDFS metadata server — one Active, one Standby |
| **ResourceManager (RM)** | YARN cluster resource manager — Active/Standby pair |
| **DESZKFailoverController** | Monitors NN health and triggers ZooKeeper-based failover |
| **JournalNode (JN)** | Stores HDFS edit logs; quorum of 3 tolerates one node failure |
| **QuorumPeerMain** | ZooKeeper server for leader election and fencing; quorum of 3 |
| **DataNode (DN)** | Stores HDFS data blocks and serves read/write requests |
| **NodeManager (NM)** | YARN worker daemon that launches and monitors containers |

### Design Rationale

**Separation of concerns** — the cluster strictly separates the control plane (master1, master2, zk_journal) from the data plane (worker1, worker2). This prevents CPU/memory contention between coordination services and data processing workloads, simplifies monitoring, and lets you scale out by simply adding worker nodes.

**Data locality** — co-locating NodeManager with DataNode (not NameNode) means YARN containers are more likely to process data from local disk, reducing network traffic.

**Quorum stability** — ZooKeeper and JournalNodes are placed on dedicated or master nodes, away from DataNode I/O pressure, preventing fsync latency spikes that could delay edit log writes or ZooKeeper heartbeats.

---

## Failure Scenarios

### Single Node Failures

| Failed Node | Impact |
|---|---|
| **master1** | ZooKeeper (master2 + zk_journal) elects new leader; ZKFC promotes master2's NN to Active; RM failover occurs if needed |
| **master2** | Symmetric to master1 |
| **zk_journal** | No impact — ZooKeeper and JN still have quorum on master1 + master2 |
| **worker1 or worker2** | HDFS loses some block replicas; YARN loses capacity but reschedules on the remaining worker |

> ⚠️ With a replication factor of 1, losing a worker node results in data loss for blocks on that node.

### Multiple / Split-Brain Failures

**master1 + zk_journal down** — ZooKeeper loses quorum; no failover is possible. JNs also lose quorum, so the NameNode stops serving metadata. The cluster becomes unavailable, which is the correct behavior — consistency takes priority.

**Network partition: master1 vs (master2 + zk_journal)** — The majority side (master2 + zk_journal) elects a ZooKeeper leader, fences master1 via ZKFC, and promotes the Standby NN. The cluster remains consistent.

**Control plane vs workers partitioned** — Workers lose heartbeats and are marked dead after a timeout. The control plane continues operating. When the partition heals, workers re-register automatically.

---

## Getting Started

### Prerequisites

- Docker & Docker Compose

### Run the Cluster

```bash
git clone https://github.com/SalmaAlgayar/hadoop_ha_cluster.git
cd hadoop_ha_cluster
docker-compose up
```

Startup is sequenced via bash scripts to ensure ZooKeeper reaches quorum before JournalNodes and NameNodes initialize.

### Verify the Cluster

```bash
# Check running daemons on any node
docker exec -it master1 jps

# Check NameNode HA status
docker exec -it master1 hdfs haadmin -getServiceState nn1
docker exec -it master1 hdfs haadmin -getServiceState nn2

# Check YARN ResourceManager HA status
docker exec -it master1 yarn rmadmin -getServiceState rm1
```

### Web UIs

| Service | URL |
|---|---|
| Active NameNode | http://master1:9870 |
| Standby NameNode | http://master2:9870 |
| YARN ResourceManager | http://master1:8088 |

---

## Key Configuration Properties

| Property | Value | Why |
|---|---|---|
| `fs.defaultFS` | `hdfs://cluster` | Must use the nameservice ID, not a specific node, for HA to work |
| `mapreduce.framework.name` | `yarn` | Routes MapReduce jobs through YARN instead of running locally |
| `yarn.app.mapreduce.am.env` | `HADOOP_MAPRED_HOME=...` | Required classpath for the AppMaster container |
| `mapreduce.map.env` / `mapreduce.reduce.env` | `HADOOP_MAPRED_HOME=...` | Required classpath for map/reduce containers |
| ZooKeeper `myid` | Unique integer per node | Without this, ZooKeeper nodes fail to form a quorum |

---

## Lessons Learned

- **SSH key setup** — `ssh-copy-id` requires password authentication to be enabled. The simplest reliable approach was generating a key on one node and manually distributing it to all others.
- **Docker image commits** — Committing a running container bakes in its CMD, causing stale startup behavior when the architecture changes. Prefer proper Dockerfiles.
- **`depends_on` is not a startup sequencer** — It only controls container start order, not process readiness. Bash scripts with explicit `sleep` / health checks were used instead.
- **ZooKeeper + JournalNodes on worker nodes** — Technically allowed, but placing I/O-sensitive coordination services alongside DataNodes causes fsync latency spikes under heavy write load. Dedicated or master nodes are the right home for them.
- **NameNode formatting** — Always clear namenode and ZooKeeper data directories between runs; stale data from previous runs causes silent failures during format and bootstrap.

---

## Repository

[github.com/SalmaAlgayar/hadoop_ha_cluster](https://github.com/SalmaAlgayar/hadoop_ha_cluster)

