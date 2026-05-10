# Playing GIF on LVGL

## Convert gif to C array

1. google lvgl online image converter or https://lvgl.io/tools/imageconverter
2. Since esphome lvgl uses lvgl v8.4, select
   **LVGL v8**
3. Upload gif file and then select
    **CF_RAW** and output format **C array**
4. Press **Convert**

## Open converted C file

1. Go the end of the file
2. You should see something like:

```c
const lv_img_dsc_t Admail = {
  .header.cf = LV_IMG_CF_RAW_CHROMA_KEYED,
  .header.always_zero = 0,
  .header.reserved = 0,
  .header.w = 50,
  .header.h = 24,
  .data_size = 1501,
  .data = Admail_map,
};
```

Need to observe the name of the variable called **Admial** . In my example, this file is called admail.c. You see references to both this variable and the filename.

## What is needed in the YAML file

1. 

```yaml
substitutions:
  gif_file: "admail.c"

esphome:
  name: gifesp32c3lvgl
  includes:
    - ${gif_file}
  platformio_options:
    build_flags: 
      - "-DLV_USE_GIF=1"
      - "-DLV_USE_IMG=1"
esp32:
  variant: esp32c3
  framework:
    type: esp-idf

# yada yada yada

lvgl:
#   displays:
#     - mylcd
  pages:
    - id: main_page
      widgets:
        - obj:
            align: TOP_MID
            layout:
              type: flex
              flex_flow: column
            width: 100%
            widgets:
              - button:
                  id: mybutton
                  on_press:
                    then:
                      - logger.log: "Button pressed"
                      - lambda: |-
                          extern const lv_img_dsc_t Admail;
                          lv_obj_t *gif = lv_gif_create(id(gif_container));
                          lv_gif_set_src(gif, &Admail);
                          lv_obj_center(gif);

                          
                      - lvgl.page.show:
                          id: gif_page

                  widgets:
                    - label:
                        text: "Press me"
    - id: gif_page
      widgets:
        - obj:
            id: gif_container
            width: 100%
            height: 100%

```