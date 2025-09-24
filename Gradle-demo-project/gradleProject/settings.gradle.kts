rootProject.name = "gradleProject"
include("infrastructure")
include("domain")
include("application")
include("domain:services")
findProject(":domain:services")?.name = "services"
