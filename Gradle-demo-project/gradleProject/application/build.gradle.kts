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
    implementation("org.jboss.resteasy:resteasy-jaxrs:3.15.6.Final")
}

tasks.test {
    useJUnitPlatform()
}