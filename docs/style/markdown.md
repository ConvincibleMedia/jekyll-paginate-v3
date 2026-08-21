# Markdown Style Guide

* Use asterisk-style bullets.
* One clear line before a heading, but two clear lines before a level 2 heading.

  ```markdown
  This is an example paragraph.


  ## This is a level 2 heading

  It contains a further heading.

  ### This is a level 3 heading.
  ```
* Indentation uses spaces.
  * In general, 2 spaces increase the indentation level, but use additional spaces when required to ensure things line up under numbered list items. E.g.:

    ```markdown
    * Bullet level 1
      * Bullet level 2
        1. Nested ordered list item
           * Nested sub-bullet
        2. Nested ordered list item
           10. Deeper nested ordered item
               * Nested sub-bullet
    ```
* Do not insert horizontal rules (`---`).
* Do not number sections.
* Don't add line-breaks to force wrap at a certain line length.