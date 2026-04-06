require("./lib").start(
 require("buttons"),
 require("ir"),
 {
  mqtt: {
   host: "hassiot.iammikhail.com"
  }
 }
)