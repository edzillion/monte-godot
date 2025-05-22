
# EZ Stats

EZ Stats simplifies your statistics needs by offering the following global functions via a sole, auto-loaded singleton script:

sanitize() - Ingests an Array with elements of any type, sanitizes non-integers/floats, and returns an Array[float]

mean() - Calculates the statistical mean (average) of a dataset

median() - Calculates the statistical median of a dataset

spread() - Calculates the statistical range of a dataset

minima() - Calculates the statistical minima of a dataset

maxima() - Calculates the statistical maxima of a dataset

variance() - Calculates the mean-based variance of a dataset

standev() - Calculates the mean-based standard deviation of a dataset

mad() - Calculates the median absolute deviation of a dataset

all() - Calculates all summary statistics above and returns them in a Dictionary


## Badges

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/license/mit)
[![GitHub](https://img.shields.io/badge/GitHub-Repo-gold.svg)](https://github.com/aaron-tundrapeaksstudios/EZ-RNG)
[![AssetLib](https://img.shields.io/badge/Godot-AssetLib-red.svg)](https://godotengine.org/asset-library/asset)
[![Godot 4.x](https://img.shields.io/badge/Godot-4.x-blue.svg)](https://godotengine.org/)
[![Godot GDScript](https://img.shields.io/badge/Godot-GDScript-purple.svg)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)
## Installation

Install from the Godot editor's AssetLib

```
  1.) Click on "AssetLib" at the top-middle of the editor
  2.) Search for "EZ Stats" without double-quotes
  3.) Click on "EZ Stats"
  4.) Click "Download"
  5.) Click "Install"
  6.) Navigate to Project -> Project Settings -> Plugins and check the "On" box 
  7.) Call the EZ Stats functions anywhere in the rest of your project's GDScript scripts via:
    7.1.) EZSTATS.sanitize()
    7.2.) EZSTATS.mean()
    7.3.) EZSTATS.median()
    7.4.) EZSTATS.spread()
    7.5.) EZSTATS.minima()
    7.6.) EZSTATS.maxima()
    7.7.) EZSTATS.variance()
    7.8.) EZSTATS.standev()
    7.9.) EZSTATS.mad()
    7.10.) EZSTATS.all()
```

Install from the .zip file

```
  1.) Download and un-zip the addons folder from this repo
  2.) If your project doesn't yet have an addons folder, paste the addons folder as-is into the root of res://
    2.1.) res:// structure should be res://addons/ez_stats/$contents
    2.2.) If you already have an addons folder, just paste the ez_stats folder into it
  3.) Navigate to Project -> Project Settings -> Plugins and check the "On" box
  4.) Call the EZ Stats functions anywhere in the rest of your project's GDScript scripts via:
    4.1.) EZSTATS.sanitize()
    4.2.) EZSTATS.mean()
    4.3.) EZSTATS.median()
    4.4.) EZSTATS.spread()
    4.5.) EZSTATS.minima()
    4.6.) EZSTATS.maxima()
    4.7.) EZSTATS.variance()
    4.8.) EZSTATS.standev()
    4.9.) EZSTATS.mad()
    4.10.) EZSTATS.all()
```
    
## Usage

#### EZSTATS.sanitize()

```gdscript
  EZSTATS.sanitize(sources: Array) -> Array[float]

  ##e.g. Sanitize a sample Array of integers and floats:

  var sample_source: Array = [1, 2.5, 3, false, "test"]
  var sanitized_source: Array[float] = EZSTATS.sanitize(sample_source)
  print(str(sanitize_source)) ##Will show [1.0, 2.5, 3.0]
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `sources` | `Array` | **Required**. Source data values in an Array

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `sanitized` | `Array[float]` | A float array containing all sanitized, integer or float only, values

#### EZSTATS.mean()

```gdscript
  EZSTATS.mean(data: Array[float], dof: float) -> float

  ##e.g. Find the mean of a sample sanitized source array

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var mean: float = EZSTATS.mean(sanitized_source, 0.001)
  print(str(mean)) ##Will return 4.625
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `mean` | `float` | A float representative of the mean of the data values

#### EZSTATS.median()

```gdscript
  EZSTATS.median(data: Array[float], dof: float) -> float

  ##e.g. Find the median of a sample sanitized source array

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var median: float = EZSTATS.median(sanitized_source, 0.01)
  print(str(median)) ##Will return 3.75
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `median` | `float` | A float representative of the median of the data values

#### EZSTATS.spread()

```gdscript
  EZSTATS.spread(data: Array[float], dof: float) -> void

  ##e.g. Find the spread of a sample sanitized source array

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var spread: float = EZSTATS.spread(sanitized_source, 0.1)
  print(str(spread)) ##Will return 9
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `mean` | `float` | A float representative of the spread of the data values

#### EZSTATS.minima()

```gdscript
  EZSTATS.minima(data: Array[float], dof: float) -> void

  ##e.g. Find the minima, smallest value, of a sample sanitized source array
  
  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var minima: float = EZSTATS.minima(sanitized_source, 0.1)
  print(str(minima)) ##Will return 1
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `mean` | `float` | A float representative of the minima data value

#### EZSTATS.maxima()

```gdscript
  EZSTATS.maxima(data: Array[float], dof: float) -> void

  ##e.g. Find the maxima, largest value, of a sample sanitized source array
  
  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var maxima: float = EZSTATS.maxima(sanitized_source, 0.1)
  print(str(maxima)) ##Will return 10
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `mean` | `float` | A float representative of the maxima data value

#### EZSTATS.variance()

```gdscript
  variance(data: Array[float], dof: float) -> float

  ##e.g Find the variance of a sample sanitized source dataset

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var variance: float = EZSTATS.variance(sanitized_source, 0.0001)
  print(str(variance)) ##Will return 15.5625
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `variance` | `float` | A float representative of the data's variance

#### EZSTATS.standev()

```gdscript
  standev(data: Array[float], dof: float) -> float

  ##e.g Find the standard deviation of a sample sanitized source dataset

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var standev: float = EZSTATS.standev(sanitized_source, 0.01)
  print(str(standev)) ##Will return 3.54
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `standev` | `float` | A float representative of the data's standard deviation

#### EZSTATS.mad()

```gdscript
  mad(data: Array[float], dof: float) -> float

  ##e.g Find the median absolute deviation of a sample sanitized source dataset

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var mad: float = EZSTATS.mad(sanitized_source, 0.001)
  print(str(mad)) ##Will return 2.875
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `data` | `Array[float]` | **Required**. Sanitized source data values in an Array[float]
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `mad` | `float` | A float representative of the data's median absolute deviation

#### EZSTATS.all()

```gdscript
  all(sources: Array, dof: float) -> Dictionary

  ##e.g Calculate all summary statistics

  var sanitized_source: Array[float] = [1, 2.5, 5, 10]
  var all: Dictionary = EZSTATS.all(sanitized_source, 0.01)
  print(str(all)) ##Will return all values rounded to the 0.01 (hundredths) place
  ##{
		##"Mean": 4.63,
		##"Median": 3.75,
		##"Spread": 9.0,
		##"Minima": 1.0,
		##"Maxima": 10.0,
		##"Variance": 15.56,
		##"Standev": 3.54,
		##"Mad": 2.88
	##}
```

| Parameters | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `sources` | `Array` | **Required**. Source data values, will be sanitized for you
| `dof` | `float` | **Required**. Degrees of Freedom, 10^n-th place

| Returns | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `results` | `Dictionary` | A dictionary containing all summary statistics

## Documentation

- [Snapped()](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-snapped)


## Acknowledgements

 - [Awesome README](https://github.com/matiassingers/awesome-readme)
 - [Godot Foundation](https://godot.foundation/)
 - [Shields.io Badges](https://shields.io/)
 - [Opensource.org License Templates](https://opensource.org/license/)


## Authors

Tundra Peaks Studios

[@aaron-tundrapeaksstudios](https://github.com/aaron-tundrapeaksstudios)


## License

[MIT](https://opensource.org/license/mit)

