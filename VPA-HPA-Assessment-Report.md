# VPA Recommendation and HPA/Infrastructure Impact Report

**Prepared:** 6 November 2026

**Cluster:** `my-gke-cluster` (`asia-south1-a`)

**Namespace:** `vivek`

**Assessment status:** Preliminary snapshot; continue observing before making resource changes

## Executive summary

Vertical Pod Autoscaling (VPA) is enabled at the GKE cluster level. A VPA named
`nginx-vpa` targets `nginx-deployment` in recommendation-only (`Off`) mode. It
does not change pod resource requests or restart pods. The second workload,
`nginx-deployment-2`, is not targeted by VPA and can serve as a comparison.

At the latest observation, VPA returned a recommendation of **1m CPU and 4Mi
memory** for the NGINX container, with an upper bound of **9m CPU and 31Mi
memory**. Both HPAs reported **0% CPU against a 70% target** and remained at
their minimum of **2 replicas**. The four NGINX pods showed **0m CPU and 2–3Mi
memory** in the point-in-time metrics snapshot.

These values indicate that the workloads were nearly idle during the snapshot;
they are **not a safe basis for reducing production requests**. The VPA was
created less than ten minutes before the latest collection, and the sample does
not cover representative traffic or a peak period. HPA status says the desired
replica count was below its minimum, so both HPAs held at two replicas. Since
VPA is in `Off` mode, this is not evidence that VPA changed HPA behavior. No
VPA-driven pod or node changes were observed or expected in `Off` mode.

## Scope and configuration

| Component | Configuration |
|---|---|
| VPA feature | Enabled at GKE cluster level |
| VPA object | `nginx-vpa`, targeting `Deployment/nginx-deployment` only |
| VPA update mode | `Off` — recommendations only; no automatic resource updates |
| Comparison workload | `nginx-deployment-2`, not targeted by VPA |
| HPA for first deployment | `nginx-hpa`; CPU target 70%; minimum 2, maximum 10 replicas |
| HPA for second deployment | `nginx-hpa-2`; CPU target 70%; minimum 2, maximum 10 replicas |
| NGINX requests per pod | 250m CPU, 256Mi memory |
| NGINX limits per pod | 500m CPU, 512Mi memory |

Both deployments were healthy in the snapshot, each reporting 2/2 ready pods.
The deployment replica counts are managed by their HPAs.

## Observed snapshot

Collected from the management server on **6 November 2026 at 12:16 UTC
(17:46 IST)**. The VPA object creation timestamp was **12:07:31 UTC**, so the
latest recommendation was observed approximately nine minutes after creation.
Node metrics below were collected at **12:17 UTC**.

### VPA recommendation for `nginx-deployment`

| Resource | Current request per pod | VPA target | Lower bound | Upper bound |
|---|---:|---:|---:|---:|
| CPU | 250m | 1m | 1m | 9m |
| Memory | 256Mi | 4Mi | 4Mi | 31Mi |

The VPA status reported `RecommendationProvided=True` and `LowConfidence=False`
at the time of collection. These status conditions do not replace a
representative observation period: the recommendation was captured shortly
after VPA creation while measured NGINX use was near zero. The low upper bounds
reflect this short, low-usage sample and should not be treated as validated
capacity requirements.

### HPA and pod status

| Deployment | HPA | CPU at snapshot | CPU target | Current replicas | Min–max |
|---|---|---:|---:|---:|---:|
| `nginx-deployment` | `nginx-hpa` | 0% | 70% | 2 | 2–10 |
| `nginx-deployment-2` | `nginx-hpa-2` | 0% | 70% | 2 | 2–10 |

Each deployment reported 2/2 ready, up-to-date, and available replicas.

### Container usage at snapshot

| Deployment | Pod CPU | Pod memory |
|---|---:|---:|
| `nginx-deployment-2` (pod 1) | 0m | 2Mi |
| `nginx-deployment-2` (pod 2) | 0m | 2Mi |
| `nginx-deployment` (pod 1) | 0m | 2Mi |
| `nginx-deployment` (pod 2) | 0m | 3Mi |

### Node usage at snapshot

Three nodes were present: two nodes in the default pool and one node in the
cluster autoscaling/NAP pool.

| Node | CPU usage | CPU usage % | Memory usage | Memory usage % |
|---|---:|---:|---:|---:|
| Default pool node 1 | 96m | 10% | 1,055Mi | 37% |
| Default pool node 2 | 143m | 15% | 1,690Mi | 60% |
| NAP pool node | 92m | 4% | 1,231Mi | 20% |

The snapshot confirms that nodes were not idle overall, even though the NGINX
containers were. Node utilization includes Kubernetes and other system
workloads and must not be attributed to NGINX or VPA from this single sample.
No events were returned by the namespace events query at capture time.

## Impact assessment

### VPA impact while in `Off` mode

- VPA calculates and reports resource recommendations for the targeted
  deployment.
- It does not update the NGINX container's 250m CPU / 256Mi memory requests.
- It does not restart or replace pods and does not directly increase or reduce
  replica count.
- It does not directly cause node scale-up or scale-down. Any observed node
  autoscaling must be evaluated against other workloads and scheduling events.
- The second deployment is outside this VPA object's target and remains a
  useful comparison workload.

### HPA interaction

- Both HPAs remain active and independently scale their respective deployments
  based on CPU utilization, with a 70% target and 2–10 replica range.
- At this snapshot both HPAs were at their minimum of two replicas and reported
  0% CPU utilization. Both HPA conditions included `ScalingLimited=True` with
  reason `TooFewReplicas`, meaning the HPA's calculated desired count was below
  the configured minimum and Kubernetes held each deployment at two replicas.
  This is consistent with the very low measured CPU use.
- With VPA in `Off`, recommended requests are not applied, so VPA does not
  change the HPA CPU-request denominator.
- If an automatic VPA update mode is considered later, changing CPU requests
  can change the utilization percentage used by a CPU-based HPA. That can
  affect replica decisions; test and review the combined behavior before
  enabling automatic VPA updates.
- HPA scaling may increase or decrease replicas independently of VPA. Record
  both pod count and recommendation whenever comparing workload behavior.

### Infrastructure and cost

No VPA-driven increase in workload resource requests, pod count, or node count
is expected in `Off` mode, and none was visible in this snapshot. The cluster
had three Ready nodes at collection time; this report cannot determine why the
third node was present or attribute it to a particular workload.

This assessment does not establish a monetary cost change. The cluster, node
pools, other workloads, and previously provisioned management VM/NAT have
their own infrastructure costs; those should be evaluated separately from the
recommendation-only VPA change.

## Findings and limitations

1. **VPA is producing a recommendation** for the intended deployment.
2. **The reported recommendation is far below configured requests**, consistent
   with the near-zero container use in the captured sample. It should not be
   interpreted as a validated right-sizing target.
3. **The HPAs were not scaling above their minimum** at this observation time.
   One snapshot cannot show how they respond to sustained or peak load.
4. **No VPA-driven infrastructure change is expected in `Off` mode.** The
   HPA's `TooFewReplicas` condition reflects its minimum replica floor under
   low CPU use; it does not demonstrate a VPA effect.
5. **This remains an early, point-in-time observation.** The latest VPA sample
   was less than ten minutes old and does not cover business traffic cycles,
   sustained load, peak requests, or longer-term memory growth.
6. **No conclusion about latency, throughput, error rates, or cost savings can
   be made** from the collected Kubernetes resource metrics alone.

## Recommended assessment plan

1. Keep `nginx-vpa` in `Off` mode throughout observation.
2. Collect the same VPA, HPA, pod, node, and event measurements at regular
   intervals during representative normal and peak traffic. Cover at least one
   complete business traffic cycle; a multi-day observation is preferable if
   traffic varies by day.
3. Record workload request volume, latency, and error rate alongside
   Kubernetes metrics. Without representative traffic, VPA recommendations
   remain indicative only.
4. Compare the VPA target/lower/upper bounds with configured requests and
   measured pod use over time. Do not reduce requests based solely on the
   current snapshot.
5. Track HPA replicas and CPU utilization for both deployments. Treat
   `nginx-deployment-2` as a comparison, not a fully isolated control, because
   both deployments share the same cluster and may experience different load.
6. Review node count, node CPU/memory, scheduling events, and pending pods
   alongside workload metrics to distinguish workload demand from system
   overhead or other cluster activity.
7. Present the time-series results and operational metrics for review before
   considering any VPA mode that applies recommendations automatically.

## Repeatable collection commands

Run these commands from the management server and retain their timestamped
output for each observation:

```bash
date -u
kubectl -n vivek describe vpa nginx-vpa
kubectl -n vivek get hpa
kubectl -n vivek get deployments
kubectl -n vivek top pods --containers
kubectl top nodes
kubectl get nodes -o custom-columns='NAME:.metadata.name,CPU_ALLOCATABLE:.status.allocatable.cpu,MEMORY_ALLOCATABLE:.status.allocatable.memory'
kubectl -n vivek get events --sort-by=.lastTimestamp | tail -15
```

## Management conclusion

The live check confirms that cluster-level VPA is providing a recommendation
for `nginx-deployment` while leaving its pod resources unchanged in `Off` mode.
Both NGINX HPAs reported 0% CPU against a 70% target. Their calculated desired
replica counts were below the configured minimum, so each deployment remained
at two replicas; this is expected under low utilization and is not an observed
VPA/HPA conflict. No VPA-driven infrastructure impact was observed. The very
low recommendation and short observation window are insufficient evidence for
right-sizing. Continue recommendation-only observation under representative
traffic, correlate results with application performance and HPA/node behavior,
and review them before enabling automatic VPA updates.
