# ------------------------------------------------------------
# Interactive Traffic Prediction Simulator (Shiny)
# A toy version of the idea behind Google Maps ETAs.
#
# To run:  install.packages("shiny")   (one time only)
#          then open this file in RStudio and click "Run App",
#          or run:  shiny::runApp("app.R")
# ------------------------------------------------------------

library(shiny)

# ---------- Simulation logic ----------
historical_speed <- function(h, free_flow = 60) {
  dip <- 25 * exp(-(h - 8)^2 / 2) + 30 * exp(-(h - 17)^2 / 2)
  free_flow - dip
}

simulate <- function(hour, accident_seg, n_phones, seed) {
  set.seed(seed)
  length_km  <- rep(2, 5)
  hist_speed <- rep(historical_speed(hour), 5)

  # What's actually happening today (unknown to the model)
  true_speed <- hist_speed * runif(5, 0.9, 1.1)
  if (accident_seg > 0) {
    true_speed[accident_seg] <- 12
    if (accident_seg > 1)
      true_speed[accident_seg - 1] <- true_speed[accident_seg - 1] * 0.6
  }

  # Live phone data: noisy readings, averaged per segment
  live_speed <- sapply(true_speed, function(s)
    mean(pmax(rnorm(n_phones, mean = s, sd = 10), 3)))

  # Blend: more phones = more weight on live data
  w_live     <- n_phones / (n_phones + 5)
  pred_speed <- w_live * live_speed + (1 - w_live) * hist_speed

  # Spread: a big slowdown also slows the segment behind it
  for (i in 2:5) {
    if (pred_speed[i] < 0.5 * hist_speed[i])
      pred_speed[i - 1] <- min(pred_speed[i - 1], 0.8 * hist_speed[i - 1])
  }

  eta <- function(speed) sum(length_km / speed) * 60
  list(
    speeds = rbind(Historical = hist_speed, Predicted = pred_speed, Actual = true_speed),
    eta    = c(Historical = eta(hist_speed), Predicted = eta(pred_speed), Actual = eta(true_speed)),
    w_live = w_live
  )
}

cols <- c(Historical = "grey70", Predicted = "steelblue", Actual = "tomato")

# ---------- User interface ----------
ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-size: 16px; }
    .eta-box { display: inline-block; width: 31%; margin: 0 1%; padding: 14px;
               border-radius: 10px; text-align: center; color: white; }
    .eta-num { font-size: 34px; font-weight: bold; }
  "))),
  titlePanel("How Google Maps Predicts Traffic: A Toy Simulator"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("hour", "Time of day (hour)", min = 0, max = 23, value = 8, step = 1),
      radioButtons("accident", "Accident on segment",
                   choices = c("None" = 0, "1" = 1, "2" = 2, "3" = 3, "4" = 4, "5" = 5),
                   selected = 3, inline = TRUE),
      sliderInput("phones", "Phones reporting per segment", min = 1, max = 100, value = 20),
      actionButton("reroll", "New random day", class = "btn-primary"),
      hr(),
      textOutput("weight"),
      helpText("Historical = usual speed at this hour.",
               "Predicted = historical blended with live phone data.",
               "Actual = what really happened.")
    ),
    mainPanel(
      uiOutput("eta_boxes"),
      br(),
      plotOutput("speed_plot", height = "420px")
    )
  )
)

# ---------- Server ----------
server <- function(input, output) {
  result <- reactive({
    simulate(input$hour, as.numeric(input$accident), input$phones,
             seed = 42 + input$reroll)
  })

  output$eta_boxes <- renderUI({
    e <- result()$eta
    box <- function(name) div(class = "eta-box", style = paste0("background:", cols[[name]], ";"),
                              div(name), div(class = "eta-num", sprintf("%.1f min", e[[name]])))
    tagList(box("Historical"), box("Predicted"), box("Actual"))
  })

  output$weight <- renderText({
    sprintf("Weight on live data: %.0f%%", 100 * result()$w_live)
  })

  output$speed_plot <- renderPlot({
    s <- result()$speeds
    colnames(s) <- paste("Seg", 1:5)
    barplot(s, beside = TRUE, col = cols, ylim = c(0, 75),
            ylab = "Speed (km/h)", main = "Speed on each 2 km road segment",
            cex.names = 1.2, cex.axis = 1.1, cex.lab = 1.2)
    legend("topright", legend = rownames(s), fill = cols, bty = "n", cex = 1.1)
  })
}

shinyApp(ui, server)
