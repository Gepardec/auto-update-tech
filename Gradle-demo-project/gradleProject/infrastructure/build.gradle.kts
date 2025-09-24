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
    implementation("org.hibernate:hibernate-core:7.1.1.Final")
}

tasks.test {
    useJUnitPlatform()
}