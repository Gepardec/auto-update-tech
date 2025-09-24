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
    implementation("javax.xml.bind:jaxb-api:2.3.1")
}

tasks.test {
    useJUnitPlatform()
}