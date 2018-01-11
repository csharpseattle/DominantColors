getDominantColors: main.cpp
	g++ -o getDominantColors main.cpp $(shell pkg-config --cflags --libs /usr/local/lib/pkgconfig/opencv.pc)
	@echo "\nSAMPLE COMMAND-LINE:"
	@echo "# use the SingleStore12.png image to find a palette of 6 dominant colors:\n"
	@echo "\t ./getDominantColors SingleStore12.png 6\n"

clean:
	rm -f quantized.png palette.png classification.png getDominantColors
