# Toolchain definitions
AS = ca65
LD = ld65

# Flags: Include search paths (-I)
ASFLAGS = -I include -I src -I src/data 
LDFLAGS = -C nes.cfg

# Target output
BUILD_DIR = build
TARGET = $(BUILD_DIR)/output.nes

# Tell make where to search for .asm files in subdirectories
vpath %.asm src include src/data

# Add all your source files here
SRC_FILES = src/kernal.asm \
            src/ppu.asm \
            src/vectors.asm \
            include/header.asm \
            src/data/palette.asm \
            src/data/font.asm \
			src/data/tables.asm \
	

# Convert source file list into object files in build/
OBJS = $(patsubst %.asm, $(BUILD_DIR)/%.o, $(notdir $(SRC_FILES)))

.PHONY: all clean

all: $(BUILD_DIR) $(TARGET)

# Create build output directory if missing
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Universal pattern rule using vpath to locate %.asm
$(BUILD_DIR)/%.o: %.asm
	$(AS) $(ASFLAGS) $< -o $@

# Link all objects into the final NES binary
$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $(TARGET)

clean:
	rm -rf $(BUILD_DIR)
