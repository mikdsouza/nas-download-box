require("./lib").start(
 require("buttons"),
 require("ir"),
 {
  mqtt: {
   host: "hass.iammikhail.com"
  }
 }
)