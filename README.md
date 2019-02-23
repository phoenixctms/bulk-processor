Phoenix CTMS
=====

This repository is a supplemental part of the Phoenix CTMS platform, see [https://github.com/phoenixctms/ctsms](https://github.com/phoenixctms/ctsms).

The Bulk-Processor is a perl-based framework for ETL programs which hosts a growing number of "projects" to cover eg.
- eCRF setup import/export
- individual eCRF data import/export/migration
- data cleaning (eg. duplicate subject signups)
- various other ETL programs (reporting, query definition import/export, ...)
- rendering tools (system usage stats, workflow diagrams, data analysis, ...)

It can be installed and executed locally, connecting to a remote Phoenix CTMS instance via Rest-API (or to PostgreSQL, MySQL, ... database directly).

Installation on Windows
-----
The following was tested on a vanilla Windows 8 VM.

1. Prerequisites:
* download and install a recent ActivePerl for Windows (eg. ActivePerl-5.26.3.2603-MSWin32-x64-a95bce075.exe)
* optional:
  - download and install GraphViz (eg. graphviz-2.38.msi), add C:\Program Files (x86)\Graphviz2.38\bin to your "Path" environment variable
  - download and install GNUPlot (eg. gp526-win64-mingw_2.exe)
  - download and install GhostScript (eg. gs926aw64.exe)
  - download and install ImageMagick (eg. ImageMagick-7.0.8-28-Q16-x64-static.exe)

2. Put together your local installation:
* download https://github.com/phoenixctms/bulk-processor/archive/master.zip and extract to C:\
* download https://github.com/phoenixctms/config-default/archive/master.zip and extract to C:\
* create a folder C:\bulk-processor
* move content from C:\bulk-processor-master to C:\bulk-processor
* move content from C:\config-default-master\bulk_processor to C:\bulk-processor
* optional: 
  - download https://github.com/xxx/config-yyy/archive/master.zip and extract to C:\
  - move content from C:\config-yyy-master\bulk_processor to C:\bulk-processor (replace existing files)

3. Install perl module dependencies:
* open Command Prompt, change to C:\bulk-processor and run
```
install_dependencies.bat
```
* done. change to a project (eg. C:\bulk-processor\CTSMS\BulkProcessor\Projects\ETL\EcrfExporter), adjust the settings in .cfg/.yml files and run
```
perl process.pl
```
