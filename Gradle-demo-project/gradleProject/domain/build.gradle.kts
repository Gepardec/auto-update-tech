plugins {
    id("java")
}

group = "at.gepardec.openrewrite"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(platform("org.junit:junit-bom:5.10.0"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    implementation("log4j:log4j:1.2.17")
}

tasks.test {
    useJUnitPlatform()
}