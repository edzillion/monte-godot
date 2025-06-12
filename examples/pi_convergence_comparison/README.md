# π Convergence Comparison: Random vs SOBOL Sampling

This example demonstrates the superior efficiency of SOBOL sampling compared to random sampling for Monte Carlo integration by estimating the value of π.

## What it does

The example runs two identical π estimation simulations:
1. **Random Sampling**: Uses standard pseudorandom number generation
2. **SOBOL Sampling**: Uses SOBOL quasi-random sequences for better space-filling properties

Both simulations use the classic Monte Carlo method of estimating π by sampling random points in a square and counting how many fall inside a circle.

## Visualization

The example generates two real-time graphs:

### 1. Convergence Graph
- **X-axis**: Number of samples processed
- **Y-axis**: Current π estimate
- **Orange line**: Random sampling convergence
- **Blue line**: SOBOL sampling convergence  
- **Black line**: True π value reference (3.14159...)

### 2. Error Graph
- **X-axis**: Number of samples processed
- **Y-axis**: Absolute error |π_estimate - π|
- **Orange line**: Random sampling error
- **Blue line**: SOBOL sampling error

## Expected Results

SOBOL sampling typically demonstrates:
- **Faster convergence** to the true π value
- **Lower error** with fewer samples
- **More stable** estimates (less oscillation)
- **Better efficiency** overall

## Configuration

You can modify the simulation parameters in `pi_convergence_comparison.gd`:

```gdscript
const N_CASES: int = 10000          # Total number of samples
const SUPER_BATCH_SIZE: int = 1000  # Batch processing size
const INNER_BATCH_SIZE: int = 100   # Inner batch size
```

## Running the Example

1. Open the scene: `res://examples/pi_convergence_comparison/pi_convergence_comparison.tscn`
2. Run the scene (F6)
3. Watch the real-time convergence comparison
4. Check the console for final statistics

## Key Learning Points

This visualization clearly shows why SOBOL sampling is preferred for Monte Carlo integration:
- **Better space coverage**: SOBOL sequences fill the space more uniformly
- **Reduced clustering**: Avoids the random clumping that can occur with pseudorandom numbers
- **Faster convergence**: Reaches acceptable accuracy with fewer samples
- **More predictable results**: Less variance between runs

This same principle applies to any Monte Carlo simulation where you want to efficiently explore a parameter space! 