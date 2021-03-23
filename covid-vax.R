library(jsonlite)
library(tidyverse)
library(lubridate)

# https://dev.socrata.com/foundry/data.cdc.gov/b7pe-5nws
"
New weekly allocations of doses are posted every Tuesday. 
Beginning the following Thursday, states can begin ordering doses from that week’s new allocation of 1st doses. 
Beginning two weeks (Pfizer) or three weeks (Moderna) from the following Sunday, states can begin ordering doses 
from that week’s new allocation of 2nd doses. After doses are ordered by states, shipments begin the following Monday. 
The entire order may not arrive in one shipment or on one day, but over the course of the week.

Second doses are opened up for orders on Sundays, at the appropriate interval two or three weeks later according to 
the manufacturer’s label, with shipments occurring after jurisdictions place orders.

Shipments of an FDA-authorized safe and effective COVID-19 vaccine continue to arrive at sites across America. 
Vaccinations began on December 14, 2020. https://www.hhs.gov/coronavirus/covid-19-vaccines/index.html 
Pfizer Vaccine Data -https://data.cdc.gov/Vaccinations/COVID-19-Vaccine-Initial-Allocations-Pfizer/saz5-9hgg 
Janssen Vaccine Data -https://data.cdc.gov/Vaccinations/COVID-19-Vaccine-Distribution-Allocations-by-Juris/w9zu-fywh
"

juris <- "jurisdiction=District%20of%20Columbia"

eps <- list(
  pfizer = "https://data.cdc.gov/resource/saz5-9hgg.json",
  moderna = "https://data.cdc.gov/resource/b7pe-5nws.json",
  jj = "https://data.cdc.gov/resource/w9zu-fywh.json"
) 
eps <- paste0(eps, juris)

get <- function(txt) {
  ddp <- fromJSON(txt) %>%
    mutate(week_of_allocations = as.Date(week_of_allocations)) %>% 
    as_tibble()
  ddp
}

mungep <- function(ddp) {
  d <- ddp %>% 
    mutate_at(3:4, function(x) as.numeric(x, digits=8))
  names(d)[3:4] <- c("first", "second")
  d %>% pivot_longer(cols=3:4)
}
mungej <- function(ddp) {
  d <- ddp %>% 
    mutate_at(3, function(x) as.numeric(x, digits=8))
  names(d)[3] <- c("full")
  d %>% pivot_longer(cols=3)
}


ds <- lapply(eps, get)
lapply(ds[3], mungej) -> ds__
lapply(ds[1:2], mungep) -> ds_
ds[1:2] <- ds_
ds[3] <- ds__

ds <- lapply(1:3, function(i) {ds[[i]] %>% mutate(type=names(ds)[i]) })
d <- do.call(rbind, ds)



# rule: 6-day lag from allocation to delivery week starting monday
dw <- d %>% mutate(offset=ifelse(name=='second' &type=='pfizer', 14+6,
                                  ifelse(name =='second'&type=='moderna', 6+21, 6))) %>%
  mutate(offset=lubridate::days(offset)) %>%
  mutate( delivery_week=week_of_allocations + offset) %>%
  arrange(delivery_week) %>%
  mutate(total=cumsum(value))

# TODO update
# hard coded from DC gov's most recent update
update <- as.Date("2021-03-19") 
dw %>% filter(delivery_week - update <=0) ->tmp
nearest_week <- tmp[which.max(tmp$delivery_week - update), "delivery_week"][[1]]
this_week <- tmp %>% filter(delivery_week == nearest_week)

write_csv(this_week, "this_week.csv")
write_csv(dw, "all_weeks.csv")

ggplot(dw) + 
  geom_rect(ymin=0, ymax=Inf, xmin=nearest_week, xmax=today(), fill='lightblue', alpha=0.1) +
  geom_line(aes(delivery_week, total )) +
  labs(title="dc vaccine allocation", 
       subtitle="across all dose types so mixing jj and others; blue = most recent week",
       caption="source CDC: https://dev.socrata.com/foundry/data.cdc.gov/b7pe-5nws")
  #eom_col(aes(delivery_week, value, fill=type))

ggsave("trajectory.png")
