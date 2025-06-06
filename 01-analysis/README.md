# Automized analysis for "secure java code upgrade"

## Prerequisites:
* mvn clean install has to result in **BUILD SUCCESS**
  * use normal settings.xml (without private registries)
* Windows: GitBash has to be available
* Permission to download node (via script) automatically
* Firewall activation towards our dependency track
  * if absolutely not possible docker must be provided for dependency track and the url must be changed *(dependency-track(-mac).sh)*

# Preparation:
* Dependency Track Api Key:
  * If you don't have a dependency track user for our dependency track (https://gepardec-dtrack.apps.cloudscale-lpg-2.appuio.cloud/) please contact [Christoph Ruhsam](mailto:christoph.ruhsam@gepardec.com).
  * If you have one please follow these steps:
    * Navigate to **Administration**:
      ![Navigate to Administration](../img/administration.png)
    * Navigate to **Access Management > Teams**:
      ![Navigate to Access Management > Teams](../img/teams.png)
    * Navigate to **Administrators** and copy the **Api Key**:
      ![Navigate to Administrators and copy the Api Key](../img/apikey.png)

## Usage:
1. Copy folder (01-analysis) into your project root directory
2. Execute
   * Change to executable
     * ```chmod +x autoUpdateAnalyse.sh ``` or <br>
       ```chmod 777 autoUpdateAnalyse.sh```<br><br>

   * Run it (works with both relative and absolute paths)
     ```bash
     # ./autoUpdateAnalyse.sh --project-root <path-to-project-root> --maven-project-root <path-to-maven-project-root> --dependency-track-api-key <dependency-track-api-key>
     ./autoUpdateAnalyse.sh --project-root ./../ --maven-project-root ./../ --dependency-track-api-key testapikey
     ```
     or
     ```bash 
     # sh autoUpdateAnalyse.sh --project-root <path-to-project-root> --maven-project-root <path-to-maven-project-root> --dependency-track-api-key <dependency-track-api-key>
     sh autoUpdateAnalyse.sh --project-root ./../ --maven-project-root ./../ --dependency-track-api-key testapikey
     ```
     
     > **INFO** <br>
     As a default setting cleanup is activated, which deletes all files that are no longer needed. If you want to change it you can extend the command above with **--cleanup false**
     
## Results:
> **INFO** <br>
    Examples, for all outcomes mentioned below, are provided in the demo-final-reports folder.

A folder **final-reports** will be created, which contains:
* auto-update-report.json,
* *<module-name>* -dependency-analysis.json &
* dependency-track-vulnerability-report.json (this one is already included in auto-update-report.json, it's still here just in case you want to check it)

> **NOTE** <br>
> Json conversion to csv is still in development.
