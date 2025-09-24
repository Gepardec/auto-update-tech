const args = process.argv.slice(1); // Skips the first two default arguments
const fs = require('fs');
const path = require('path');

const AUTO_UPDATE_REPORT_FILE = "auto-update-report.json"
const DEPENDENCY_RELOCATED = "dependency-relocated-date.json"
const RENOVATE_FILTERED = "renovate-filtered.json"
const DEPENDENCY_TRACK_VULNERABILITY_REPORT = "dependency-track-vulnerability-report.json"
const DEPENDENCY_TRACK_POLICY_VIOLATIONS = "dependency-track-policy-violations.json"
const PROJECT_ROOT_PATH = args[1]
const BUILD_TOOL = args[2]
const AUTO_UPDATE_REPORT_PATH = __dirname


let customJsonModuleReport = []

/**
 * Read dependency-relocated-date.json and extract information
 */
function getTreeInformationWithRelocations(){
    let files = findFilesRecursive(PROJECT_ROOT_PATH, DEPENDENCY_RELOCATED);

    for(let file of files){
        let relocatedData = require(file);

        let dependencies = relocatedData.dependencies

        for (let dependency of dependencies) {

            let foundIndex = customJsonModuleReport.findIndex((item) =>
                item.groupId === dependency.groupId &&
                item.artifactId === dependency.artifactId &&
                item.version === dependency.version
            );

            if (foundIndex == -1) {
                customJsonModuleReport.push(
                    {
                        groupId : dependency.groupId,
                        artifactId : dependency.artifactId,
                        version : dependency.version,
                        newVersions : [],
                        scope : dependency.scope,
                        lastUpdatedDate : dependency.lastUpdatedDate,
                        relocations : dependency.relocations !== undefined ? dependency.relocations : [],
                        vulnerabilities : []
                    }
                )
            }
        }
    }
}

/**
 * Read filtered_log from renovate and extract:
 *  gorupId
 *  artifactId
 *  newVersions
 */
function getRenovateInformation() {
    let files = findFilesRecursive(PROJECT_ROOT_PATH, RENOVATE_FILTERED);

    for(let file of files){
        let data = require(file);
        let entries = null;
        if (BUILD_TOOL === "Maven"){
            entries = data.config.maven[0].deps
        }
        if (BUILD_TOOL === "Gradle"){
            entries = data.config.gradle[0].deps
        }
        for (let e of entries) {
            if (e.updates.length > 0) {
                let updateInformationList = getUpdateInformation(e);
                let groupId = e.depName.split(":")[0]
                let artifactId = e.depName.split(":")[1]

                let foundIndex = customJsonModuleReport.findIndex((item) =>
                    item.groupId === groupId &&
                    item.artifactId === artifactId &&
                    item.version === e.currentValue
                )

                if(foundIndex >= 0){
                    customJsonModuleReport[foundIndex].newVersions = JSON.parse(JSON.stringify(updateInformationList))
                }else{
                    customJsonModuleReport.push(
                        {
                            groupId: groupId,
                            artifactId: artifactId,
                            version: e.currentValue,
                            newVersions: JSON.parse(JSON.stringify(updateInformationList)),
                            scope : "",
                            lastUpdatedDate : "",
                            relocations : [],
                            vulnerabilities : []
                        }
                    )
                }
            }
        }
    }
}

/**
 * Read dependency-track File
 * @param filePath
 */
function getDependencyTrackInformation(){
    //add here
    let dependencyTrackData = require(AUTO_UPDATE_REPORT_PATH + "/" + DEPENDENCY_TRACK_VULNERABILITY_REPORT);

    for (let entry of dependencyTrackData) {
        let groupId = entry.component.group;
        let artifactId = entry.component.name;
        let version = entry.component.version;
        let vulnerability = {
            vulnId: entry.vulnerability.vulnId,
            description: entry.vulnerability.description,
            severity: entry.vulnerability.severity,
            epssScore: entry.vulnerability.epssScore
        };

        let foundIndex = customJsonModuleReport.findIndex((item) =>
            item.groupId === groupId &&
            item.artifactId === artifactId &&
            item.version === version
        );

        if (foundIndex >= 0) {
            // Entry exists, append vulnerability to existing vulnerabilities array or create it
            if (!customJsonModuleReport[foundIndex].vulnerabilities) {
                customJsonModuleReport[foundIndex].vulnerabilities = [];
            }
            customJsonModuleReport[foundIndex].vulnerabilities.push(vulnerability);
        } else {
            // Entry does not exist, create new entry with vulnerability
            customJsonModuleReport.push({
                groupId: groupId,
                artifactId: artifactId,
                version: version,
                newVersions: [],
                scope : "",
                lastUpdatedDate : "",
                relocations : [],
                vulnerabilities: [vulnerability],
            });
        }
    }
}

/**
 * Read dependency-track File
 * @param filePath
 */
function getDependencyTrackPolicyViolationInformation(){
    //add here
    let dependencyTrackData = require(AUTO_UPDATE_REPORT_PATH + "/" + DEPENDENCY_TRACK_POLICY_VIOLATIONS);

    for (let entry of dependencyTrackData) {
        let groupId = entry.component.group;
        let artifactId = entry.component.name;
        let version = entry.component.version;
        let policyViolation = {
            componentUuid: entry.component.uuid,
            violationState: entry.violationState,
            type: entry.type,
            policyName: entry.policyName
        };

        let foundIndex = customJsonModuleReport.findIndex((item) =>
            item.groupId === groupId &&
            item.artifactId === artifactId
        );

        if (foundIndex >= 0) {
            // Entry exists, append vulnerability to existing vulnerabilities array or create it
            if (!customJsonModuleReport[foundIndex].policyViolations) {
                customJsonModuleReport[foundIndex].policyViolations = [];
            }
            customJsonModuleReport[foundIndex].policyViolations.push(policyViolation);
        } else {
            // Entry does not exist, create new entry with vulnerability
            customJsonModuleReport.push({
                groupId: groupId,
                artifactId: artifactId,
                version: version,
                newVersions: [],
                scope : "",
                lastUpdatedDate : "",
                relocations : [],
                vulnerabilities: [],
                policyViolations: [policyViolation]
            });
        }
    }
}

/**
 * Iterate trough Array of Updates and extract information -> Helper Function for getRenovateInformations
 * @param Updates part of JSON
 * @returns Array of updateInformations
 */
function getUpdateInformation(e) {
    let updateInformationList = []

    for (let update of e.updates) {
        let major = ""
        let nonMajor = ""
        let updateType = ""

        if ((update.bucket === "non-major") || (update.bucket === "major")) {
            nonMajor = update.newVersion
            updateType = update.updateType

            updateInformationList.push(
                {
                    "major": major,
                    "non-major": nonMajor,
                    "updateType": updateType
                }
            )

        }
    }
    return updateInformationList;
}

function findFilesRecursive(directory, targetFilename, results = []) {
    const files = fs.readdirSync(directory);

    files.forEach(file => {
        const filePath = path.join(directory, file);
        const stats = fs.statSync(filePath);

        if (stats.isDirectory()) {
            // **Skip "auto-update-report" directory**
            if (file !== "auto-update-report") {
                findFilesRecursive(filePath, targetFilename, results);
            }
        } else if (file === targetFilename) {
            results.push(filePath);
        }
    });

    return results;
}


/**
 * HERE WE ITERATE THROUGH ALL OUR JSONS AND EXTRACT THE INFORMATION
 * AT THE END, EVERYTHING SHOULD BE IN THE CUSTOMJSONMODULEREPORT VARIABLE
 */
getTreeInformationWithRelocations();
getRenovateInformation();
getDependencyTrackInformation();
getDependencyTrackPolicyViolationInformation();



fs.writeFileSync("./../final-reports/" + AUTO_UPDATE_REPORT_FILE, JSON.stringify(customJsonModuleReport), 'utf8');