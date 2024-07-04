const express = require('express');
const bodyParser = require('body-parser');
const app = express();
const port = process.env.PORT || 3000;

app.use(bodyParser.json());

// Fast GET endpoint
app.get('/fast', (req, res) => {
  res.send('This is a fast endpoint!');
});

// Slow GET endpoint
app.get('/slow', (req, res) => {
  setTimeout(() => {
    res.send('This is a slow endpoint!');
  }, 1000); // 1000ms delay to ensure it fails the performance test
});

// Another fast GET endpoint
app.get('/another-fast', (req, res) => {
  res.send('This is another fast endpoint!');
});

// Fast POST endpoint
app.post('/fast-post', (req, res) => {
  res.send({ message: 'This is a fast POST endpoint!', received: req.body });
});

app.put('/fast-put', (req, res) => {
  res.send({ message: 'This is a fast PUT endpoint!', received: req.body });
});

app.delete('/slow-delete', (req, res) => {
  setTimeout(() => {
    res.send({ message: 'This is a slow DELETE endpoint!', received: req.body });
  }, 1000); // 1000ms delay to ensure it fails the performance test
});

app.listen(port, () => {
  console.log(`Server listening at http://localhost:${port}`);
});