package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
)

type Video struct {
	Name   string `json:"name"`
	URLSet string `json:"urlset"`
}

func main() {
	http.HandleFunc("/records/", handleGetRecords)
	http.HandleFunc("/videos/", handleGetVideos)
	http.ListenAndServe(":3000", nil)
}

func handleGetRecords(w http.ResponseWriter, r *http.Request) {
	streamName := filepath.Base(r.URL.Path)
	videoDir := "/data/records/"

	files, err := os.ReadDir(videoDir)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	pattern := regexp.MustCompile(fmt.Sprintf("%s-.*\\.mp4$", streamName))

	var videoFiles []string
	for _, file := range files {
		if !file.IsDir() && pattern.MatchString(file.Name()) {
			videoFiles = append(videoFiles, file.Name())
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(videoFiles)
}

func handleGetVideos(w http.ResponseWriter, r *http.Request) {
	videoDir := "/data/vod/"

	files, err := os.ReadDir(videoDir)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	videos := make(map[string]*Video)
	pattern := regexp.MustCompile(`^(.*)_(\d+p)\.mp4$`)

	for _, file := range files {
		name := file.Name()
		if !file.IsDir() {
			matches := pattern.FindStringSubmatch(name)
			if len(matches) == 3 {
				videoName, resolution := matches[1], matches[2]

				if _, exists := videos[videoName]; !exists {
					videos[videoName] = &Video{
						Name:   videoName,
						URLSet: videoName + "_,",
					}
				}
				videos[videoName].URLSet += resolution + ","
			}
		}
	}

	videoSlice := make([]Video, 0, len(videos))
	for _, video := range videos {
		video.URLSet += ".mp4"
		videoSlice = append(videoSlice, *video)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(videos)
}
