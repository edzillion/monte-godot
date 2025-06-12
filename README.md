# Monte Godot

Monte Godot is a GDScript-based Monte Carlo simulation framework for the Godot Engine. It allows users to define and run complex simulations, leveraging Godot's threading capabilities for efficient processing.

## Core Features

*   **Job-Based Simulations:** Define simulations using `JobConfig` resources, specifying input variables (`InVar`), output variables (`OutVar`), and custom processing functions.
*   **Flexible Callbacks:** Provide your own GDScript functions for preprocessing, running, and postprocessing each simulation case.
*   **Parallel Processing:** Utilizes Godot's `WorkerThreadPool` via a `BatchProcessor` to run simulation cases in parallel, significantly speeding up large jobs.
*   **Memory Optimization:** Implements strategies to handle a large number of simulation cases without exhausting system memory.
*   **Statistical Utilities:** Designed to integrate with statistical libraries (like the `EZ-Stats` and `godot-stat-math` addons) for generating input distributions and analyzing results.

## Memory Optimization Strategies

Running simulations with a very high number of cases (`n_cases` in `JobConfig`) can be memory-intensive if all simulation `Case` objects are generated and stored in memory simultaneously. Monte Godot employs the following strategies to mitigate this:

### 1. Super-Batches (`super_batch_size`)

*   `MonteGodot` processes the total `n_cases` configured for a job in chunks called "super-batches". The size of these is determined by `JobConfig.super_batch_size`.
*   Instead of creating all `Case` objects for the entire job at once, `MonteGodot` generates `Case` objects only for the *current* super-batch.
*   This approach significantly limits the peak number of `Case` objects that the main `MonteGodot` process directly manages at any given time (for preprocessing, dispatching to `BatchProcessor`, and postprocessing).
*   Once a super-batch is fully processed, the `Case` objects from that specific super-batch are released from the main processing loop. If `JobConfig.save_case_data` is `false`, these `Case` objects become eligible for garbage collection, freeing up memory before the next super-batch begins.

### 2. Inner Batches (`inner_batch_size`)

*   The `BatchProcessor` receives the `Case` objects from a super-batch and further divides them into smaller "inner batches" based on `JobConfig.inner_batch_size`.
*   These inner batches are then submitted as task groups to Godot's `WorkerThreadPool` for parallel execution of the `run_callable`.
*   While `inner_batch_size` is primarily focused on managing the granularity of work distributed to threads, it also contributes to a more controlled and streamed flow of data through the `BatchProcessor` and into the worker threads. This prevents an excessive number of tasks from being queued or actively managed by the thread pool system at any single moment.

### 3. Conditional Case Data Storage (`save_case_data`)

*   The `JobConfig.save_case_data` flag (boolean) plays a crucial role in managing memory for the final results.
    *   If `true`, all processed `Case` objects (including their input and output values) are collected and stored by `MonteGodot` for the entire job. This allows for detailed inspection of every case but can be memory-intensive for jobs with millions of cases.
    *   If `false` (the default), `MonteGodot` does *not* accumulate the full `Case` objects after they are postprocessed. Instead, only the raw data from their `OutVal`s (output values) is extracted. This raw data is then aggregated into summary `OutVar` objects for the job.
*   Setting `save_case_data` to `false` dramatically reduces the memory footprint for storing the final results of a large simulation, as only the aggregated output statistics (`OutVar`s) are retained, not every individual `Case` object. This is often suitable when the primary interest is in the overall statistical distribution of outputs rather than the specifics of each individual simulation run.

By tuning `super_batch_size`, `inner_batch_size`, and `save_case_data`, users can effectively manage memory usage and run simulations with a very large number of cases on systems with limited RAM.

## Getting Started

*(TODO: Add instructions on how to set up and run a basic simulation using Monte Godot)*

## Examples

*(TODO: Link to or describe example projects, e.g., Poker Hands simulation)* 