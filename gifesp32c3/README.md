Use the min_spiffs.csv from https://github.com/espressif/arduino-esp32/blob/master/tools/partitions/min_spiffs.csv

if using home assistant addon, the path might be /config/esphome/....

  gif_file: "https://web.archive.org/web/20090822023530/http://geocities.com/Tokyo/Towers/2543/undress.gif"


# things i tried

- got gif from gifcities 

1. Change from arduino to esp-idf
2. change partition table partitions.csv from default to min_spiffs.csv
3. used https://ezgif.com/optimize and remove every 4th frame - this allowed to compile
   but then go RAM issues and went into boot loop
4. reduce the size of gif to 80x80 https://ezgif.com/resize