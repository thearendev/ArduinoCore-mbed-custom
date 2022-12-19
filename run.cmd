SET WORKDIR=%cd:\=/%

docker run -v "%WORKDIR%/patches:/patches" -v "%WORKDIR%/dist:/dist" --rm arduino-core-mbed-custom
